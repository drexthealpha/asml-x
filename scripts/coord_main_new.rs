fn main() -> Result<(), Box<dyn std::error::Error>> {
    let repo_root = std::env::var("ASML_REPO")
        .unwrap_or_else(|_| "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X".to_string());
    let port: u16 = std::env::var("ASML_COORD_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8787);

    let d = Deployments::load(&repo_root)?;
    let client = ChainClient::new(RPC, Some(FALLBACK.to_string()));
    let chain_id = client.chain_id()?;
    if chain_id != 1952 {
        return Err(format!("wrong chain {chain_id}, expected 1952").into());
    }

    let state = Arc::new(Mutex::new(State::new()));
    let limit = state.lock().expect("fresh mutex").limit_per_minute;

    // WORKER COUNT. Eight is enough to absorb the 40-request burst that stalled the previous
    // server while staying far below anything that could exhaust the RPC endpoint: each worker
    // holds at most one in-flight chain read, and the snapshot cache means most requests do none.
    // Not made configurable, because a knob nobody tunes is a knob that misleads.
    let workers: usize = 8;

    let server = Arc::new(Server::http(("127.0.0.1", port)).map_err(|e| e.to_string())?);

    println!("ASML-X coordination API");
    println!("  listening   http://127.0.0.1:{port}");
    println!("  chain       {chain_id} (verified)");
    println!("  server      tiny_http, {workers} worker threads");
    println!("  endpoints   GET /health  GET /thesis  GET /capacity");
    println!("              POST /quote  POST /accept");
    println!("  auth        x-api-key header, demo keys: demo-agent-key-1, demo-agent-key-2");
    println!("  quote ttl   {QUOTE_TTL_MS} ms, rate limit {limit}/min per caller");
    println!();

    let mut handles = Vec::new();
    for _ in 0..workers {
        let server = Arc::clone(&server);
        let state = Arc::clone(&state);
        // Each worker owns its own chain client and market-intel buffer. They are cheap, and
        // sharing them would put a lock around every chain read, which is the serialisation this
        // whole change exists to remove.
        let client = ChainClient::new(RPC, Some(FALLBACK.to_string()));
        let risk = RiskEngine::new(Limits::conservative());
        let venue = d.venue;
        let guard = d.guard;
        let market_word = d.market_word;

        handles.push(std::thread::spawn(move || {
            let mut intel = MarketIntel::new(32);
            loop {
                let mut request = match server.recv() {
                    Ok(r) => r,
                    Err(_) => break,
                };
                let (status, body) = handle(
                    &mut request,
                    &state,
                    &client,
                    &risk,
                    &mut intel,
                    venue,
                    guard,
                    market_word,
                    chain_id,
                );
                let _ = request.respond(json_response(status, &body));
            }
        }));
    }

    for h in handles {
        let _ = h.join();
    }
    Ok(())
}

/// One request, start to finish, returning the status and body rather than writing them.
///
/// Every early exit is a `return` of a value now. The previous version used `respond(); continue;`
/// inside the accept loop, which is why this could not be a small edit: a handler that runs on a
/// worker has to hand its answer back.
#[allow(clippy::too_many_arguments, clippy::too_many_lines)]
fn handle(
    request: &mut tiny_http::Request,
    state: &Arc<Mutex<State>>,
    client: &ChainClient,
    risk: &RiskEngine,
    intel: &mut MarketIntel,
    venue: Address,
    guard: Address,
    market_word: Word,
    chain_id: u64,
) -> (u16, Value) {
    let method = request.method().as_str().to_string();
    let path = request.url().split('?').next().unwrap_or("").to_string();

    let mut headers: HashMap<String, String> = HashMap::new();
    for h in request.headers() {
        headers.insert(
            h.field.as_str().as_str().to_lowercase(),
            h.value.as_str().to_string(),
        );
    }

    let mut body_text = String::new();
    let _ = request.as_reader().read_to_string(&mut body_text);
    let body: Value = serde_json::from_str(&body_text).unwrap_or(Value::Null);

    // ---- unauthenticated endpoint ----
    if method == "GET" && path == "/health" {
        let s = state.lock().expect("state mutex");
        return (
            200,
            json!({
                "ok": true, "chain_id": chain_id,
                "served": s.served, "refused": s.refused,
                "protocol_version": "1.0.0"
            }),
        );
    }

    // ---- auth and rate limit, both under one short lock ----
    let caller = {
        let mut s = state.lock().expect("state mutex");
        match headers
            .get("x-api-key")
            .and_then(|k| s.api_keys.get(k))
            .cloned()
        {
            Some(c) => c,
            None => {
                s.refused += 1;
                return (401, json!({"error": "missing or unknown x-api-key"}));
            }
        }
    };

    {
        let mut s = state.lock().expect("state mutex");
        if !s.rate_ok(&caller) {
            s.refused += 1;
            let limit = s.limit_per_minute;
            return (
                429,
                json!({"error": "rate limit exceeded", "limit_per_minute": limit}),
            );
        }
    }

    // ---- snapshot, served from the shared cache ----
    //
    // The lock is taken to READ the cache and released before any chain read. Holding it across the
    // network call would reintroduce exactly the serialisation this change removes: every worker
    // would queue behind one slow RPC round trip, which is the original bug with more threads.
    let req_now = now_ms();
    let cached = {
        let s = state.lock().expect("state mutex");
        s.snapshot
            .as_ref()
            .filter(|(_, at)| req_now.saturating_sub(*at) < SNAPSHOT_TTL_MS)
            .map(|(snap, at)| (snap.clone(), *at))
    };

    let (snap, snapshot_fetched_at) = match cached {
        Some(pair) => pair,
        None => match read_snapshot(client, venue) {
            Ok(s) => {
                let mut st = state.lock().expect("state mutex");
                st.snapshot = Some((s.clone(), req_now));
                (s, req_now)
            }
            Err(e) => {
                let mut st = state.lock().expect("state mutex");
                st.refused += 1;
                return (503, json!({"error": format!("chain read failed: {e}")}));
            }
        },
    };
    let snapshot_age_ms = req_now.saturating_sub(snapshot_fetched_at);
    let signals = intel.observe(&snap, snap.chain_time_ms);

    // Guard state shares the snapshot's cache window, for the same reason: two more round trips per
    // request is what made the rate limit unenforceable in v1.
    let need_guard = {
        let s = state.lock().expect("state mutex");
        snapshot_age_ms == 0 || s.guard_state.is_none()
    };
    if need_guard {
        let killed = client.call_bool(guard, "killed()", &[]).unwrap_or(false);
        let exposure_wei = client
            .call_u128(guard, "exposureOf(bytes32)", &[market_word])
            .unwrap_or(0);
        let mut s = state.lock().expect("state mutex");
        s.guard_state = Some((
            killed,
            market_intel::wei_to_micro(i128::try_from(exposure_wei).unwrap_or(0)),
        ));
    }
    let (killed, exposure) = {
        let s = state.lock().expect("state mutex");
        s.guard_state.unwrap_or((false, 0))
    };

    let mut ctx = RiskContext::healthy_at(snap.chain_time_ms);
    ctx.manual_kill = killed;
    let portfolio = Portfolio {
        free_margin_micro: 1_000 * MICRO,
        ..Default::default()
    };

    match (method.as_str(), path.as_str()) {
        ("GET", "/thesis") => {
            let (thesis, confidence) = MarketIntel::thesis(&signals);
            state.lock().expect("state mutex").served += 1;
            (
                200,
                json!({
                    "market": "tBASE/tQUOTE",
                    "block": snap.block_number,
                    "thesis": thesis,
                    "confidence_bps": confidence,
                    "spread_bps": signals.spread_bps.as_ref().map(|e| e.value.to_string()),
                    "imbalance_bps": signals.imbalance_bps.as_ref().map(|e| e.value.to_string()),
                    "live_orders": signals.live_order_count,
                    "snapshot_age_ms": snapshot_age_ms,
                    "halted": killed
                }),
            )
        }

        ("GET", "/capacity") => {
            // Remaining headroom, discovered by asking the risk engine rather than by recomputing
            // limits here. Two implementations of the same limit is how they end up disagreeing.
            let mut permitted = 0i128;
            let mut refusal = None;
            for step in 1..=25i128 {
                let size = step * MICRO / 2;
                let intent = OrderIntent {
                    market: MarketId::new("tBASE/tQUOTE"),
                    kind: InstrumentKind::Spot,
                    side: Side::Buy,
                    size_micro: size,
                    limit_price_micro: MICRO,
                    decision_id: 0,
                };
                match risk.evaluate(&intent, &portfolio, &ctx) {
                    Ok(_) => permitted = size,
                    Err(r) => {
                        refusal = Some(format!("{r:?}"));
                        break;
                    }
                }
            }
            state.lock().expect("state mutex").served += 1;
            (
                200,
                json!({
                    "max_permitted_size_micro": permitted.to_string(),
                    "current_exposure_micro": exposure.to_string(),
                    "first_refusal_beyond": refusal,
                    "halted": killed
                }),
            )
        }

        ("POST", "/quote") => {
            let size_micro = body
                .get("size_micro")
                .and_then(Value::as_str)
                .and_then(|s| s.parse::<i128>().ok())
                .unwrap_or(0);
            let side = match body.get("side").and_then(Value::as_str).unwrap_or("buy") {
                "sell" => Side::Sell,
                _ => Side::Buy,
            };

            if size_micro <= 0 {
                state.lock().expect("state mutex").refused += 1;
                return (
                    400,
                    json!({"error": "size_micro must be a positive integer string"}),
                );
            }

            // Price the quote off the live book, refusing if there is no reference.
            let reference = match (side, signals.best_ask, signals.best_bid) {
                (Side::Buy, Some(ask), _) => ask,
                (Side::Sell, _, Some(bid)) => bid,
                _ => {
                    state.lock().expect("state mutex").refused += 1;
                    return (
                        409,
                        json!({"error": "no reference price on the requested side"}),
                    );
                }
            };

            let intent = OrderIntent {
                market: MarketId::new("tBASE/tQUOTE"),
                kind: InstrumentKind::Spot,
                side,
                size_micro,
                limit_price_micro: reference,
                decision_id: 0,
            };

            // THE point: an external caller goes through the same gate.
            match risk.evaluate(&intent, &portfolio, &ctx) {
                Err(r) => {
                    state.lock().expect("state mutex").refused += 1;
                    (
                        409,
                        json!({
                            "error": "risk gate refused",
                            "refusal": format!("{r:?}"),
                            "rwa_specific": r.is_rwa_specific()
                        }),
                    )
                }
                Ok(approved) => {
                    let id = NEXT_QUOTE_ID.fetch_add(1, Ordering::SeqCst);
                    let issued = now_ms();
                    let q = Quote {
                        id,
                        market: "tBASE/tQUOTE".to_string(),
                        side: format!("{side:?}"),
                        size_micro,
                        price_micro: reference,
                        issued_at_ms: issued,
                        expires_at_ms: issued + QUOTE_TTL_MS,
                        caller: caller.clone(),
                        consumed: false,
                    };
                    {
                        let mut s = state.lock().expect("state mutex");
                        s.quotes.insert(id, q.clone());
                        s.served += 1;
                    }
                    (
                        200,
                        json!({
                            "quote_id": id,
                            "market": q.market,
                            "side": q.side,
                            "size_micro": q.size_micro.to_string(),
                            "price_micro": q.price_micro.to_string(),
                            "expires_at_ms": q.expires_at_ms,
                            "ttl_ms": QUOTE_TTL_MS,
                            "requires_human_approval": approved.requires_human_approval(),
                            "block": snap.block_number
                        }),
                    )
                }
            }
        }

        ("POST", "/accept") => {
            let id = body.get("quote_id").and_then(Value::as_u64).unwrap_or(0);
            let now = now_ms();
            let mut s = state.lock().expect("state mutex");
            match s.quotes.get_mut(&id) {
                None => {
                    s.refused += 1;
                    (404, json!({"error": "unknown quote_id"}))
                }
                Some(q) if q.caller != caller => {
                    s.refused += 1;
                    (403, json!({"error": "quote belongs to a different caller"}))
                }
                Some(q) if q.consumed => {
                    s.refused += 1;
                    (409, json!({"error": "quote already consumed"}))
                }
                Some(q) if now > q.expires_at_ms => {
                    let ago = now - q.expires_at_ms;
                    s.refused += 1;
                    (
                        410,
                        json!({"error": "quote expired", "expired_ms_ago": ago}),
                    )
                }
                Some(q) => {
                    q.consumed = true;
                    let accepted = q.clone();
                    s.served += 1;
                    (
                        200,
                        json!({
                            "accepted": true,
                            "quote_id": accepted.id,
                            "market": accepted.market,
                            "side": accepted.side,
                            "size_micro": accepted.size_micro.to_string(),
                            "price_micro": accepted.price_micro.to_string(),
                            "held_ms": now - accepted.issued_at_ms,
                            "note": "settlement is performed by the brain runtime; this endpoint records acceptance"
                        }),
                    )
                }
            }
        }

        _ => {
            state.lock().expect("state mutex").refused += 1;
            (404, json!({"error": "unknown endpoint"}))
        }
    }
}
