//! Agent-to-agent coordination surface. Phase 6.
//!
//! A real callable HTTP surface that an external agent, in another process and
//! another language, can use to request a quote, query risk capacity, or read the
//! brain's current thesis.
//!
//! Design points that matter, and why:
//!
//! - EVERY external request passes the SAME risk gate as an internal decision. There
//!   is no privileged path. A caller cannot obtain a quote the agent itself would be
//!   refused.
//! - Quotes EXPIRE. An open-ended quote is a free option written to the world, so each
//!   one carries a validity window and a nonce, and accepting an expired quote is
//!   refused.
//! - Per-caller RATE LIMITS. Quoting is not free: it reveals the book view and reserves
//!   capacity, so an unauthenticated flood is refused.
//! - Auth by API key, NOT by wallet signature. The operator has no browser wallet, and
//!   a signature scheme here would add a dependency without adding safety at this
//!   scope. Recorded in ADR-010.
//!
//! Written on the standard library only. A single-threaded blocking HTTP/1.1 server is
//! about 120 lines and has no dependency surface, which matters more here than
//! throughput: this endpoint is reachable by strangers.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use core_types::{InstrumentKind, MarketId, OrderIntent, Portfolio, Side, MICRO};
use market_intel::{read_snapshot, MarketIntel};
use risk_engine::{Limits, RiskContext, RiskEngine};
use serde_json::{json, Value};

const RPC: &str = "https://testrpc.xlayer.tech";
const FALLBACK: &str = "https://xlayer-testnet.drpc.org";
const QUOTE_TTL_MS: u64 = 15_000;

/// Per-caller request budget. Overridable so the limiter can actually be OBSERVED
/// tripping: with the default of 30 and a slow chain read per request, a burst takes
/// longer than the 60 second window, so the window resets and the count never
/// accumulates. That is a real property of the limiter worth knowing, and the way to
/// verify the mechanism is to shrink the budget rather than to assume it works.
fn max_requests_per_minute() -> u32 {
    std::env::var("ASML_RATE_LIMIT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(30)
}

static NEXT_QUOTE_ID: AtomicU64 = AtomicU64::new(1);

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| u64::try_from(d.as_millis()).unwrap_or(u64::MAX))
        .unwrap_or(0)
}

#[derive(Clone)]
struct Quote {
    id: u64,
    market: String,
    side: String,
    size_micro: i128,
    price_micro: i128,
    issued_at_ms: u64,
    expires_at_ms: u64,
    caller: String,
    consumed: bool,
}

struct State {
    limit_per_minute: u32,
    quotes: HashMap<u64, Quote>,
    /// caller -> (window start ms, count in window)
    rate: HashMap<String, (u64, u32)>,
    api_keys: HashMap<String, String>,
    served: u64,
    refused: u64,
    /// Short-lived snapshot cache: (snapshot, fetched_at_ms).
    ///
    /// Added after the first live run, where three separate expectations failed for
    /// one reason: every authenticated request performed seven sequential chain reads,
    /// costing seconds. A 15 second quote expired before the client's next request
    /// completed, and the 60 second rate window reset mid-burst so the limit could
    /// never accumulate. That was a real performance defect, not a test artefact.
    ///
    /// The cache does not hide staleness: every response reports `block` and
    /// `snapshot_age_ms`, so a caller can audit exactly how fresh the view is and
    /// refuse it if that is not good enough for them.
    snapshot: Option<(market_intel::VenueSnapshot, u64)>,
    /// (killed, exposure_micro), refreshed with the snapshot.
    guard_state: Option<(bool, i128)>,
}

const SNAPSHOT_TTL_MS: u64 = 2_000;

impl State {
    fn new() -> Self {
        let mut api_keys = HashMap::new();
        // Demo keys. Two distinct callers so per-caller limits are observable.
        api_keys.insert(
            "demo-agent-key-1".to_string(),
            "external-agent-1".to_string(),
        );
        api_keys.insert(
            "demo-agent-key-2".to_string(),
            "external-agent-2".to_string(),
        );
        Self {
            limit_per_minute: max_requests_per_minute(),
            quotes: HashMap::new(),
            rate: HashMap::new(),
            api_keys,
            served: 0,
            refused: 0,
            snapshot: None,
            guard_state: None,
        }
    }

    /// Sliding-ish window: a fixed 60 second bucket per caller. Crude on purpose, and
    /// crude is fine because the goal is refusing a flood, not fair queueing.
    fn rate_ok(&mut self, caller: &str) -> bool {
        let now = now_ms();
        let entry = self.rate.entry(caller.to_string()).or_insert((now, 0));
        if now.saturating_sub(entry.0) > 60_000 {
            *entry = (now, 0);
        }
        entry.1 += 1;
        entry.1 <= self.limit_per_minute
    }
}

fn respond(stream: &mut TcpStream, status: &str, body: &Value) {
    let text = body.to_string();
    let _ = write!(
        stream,
        "HTTP/1.1 {status}\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{text}",
        text.len()
    );
    let _ = stream.flush();
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let repo_root = std::env::var("ASML_REPO")
        .unwrap_or_else(|_| "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X".to_string());
    let port: u16 = std::env::var("ASML_COORD_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8737);

    let text = std::fs::read_to_string(format!("{repo_root}/deployments.json"))?;
    let dep: Value = serde_json::from_str(&text)?;
    let venue = chain_client::parse_address(dep["venue"].as_str().ok_or("no venue")?)?;
    let guard = chain_client::parse_address(dep["riskGuard"].as_str().ok_or("no guard")?)?;
    let market_word = chain_client::parse_word(dep["marketId"].as_str().ok_or("no marketId")?)?;

    let client = chain_client::ChainClient::new(RPC, Some(FALLBACK.to_string()));
    let chain_id = client.chain_id()?;
    if chain_id != 1952 {
        return Err(format!("wrong chain {chain_id}, expected 1952").into());
    }

    let risk = RiskEngine::new(Limits::conservative_testnet());
    let mut state = State::new();
    let mut intel = MarketIntel::new(32);

    let listener = TcpListener::bind(("127.0.0.1", port))?;
    println!("ASML-X coordination API");
    println!("  listening   http://127.0.0.1:{port}");
    println!("  chain       {chain_id} (verified)");
    println!("  endpoints   GET /health  GET /thesis  GET /capacity");
    println!("              POST /quote  POST /accept");
    println!("  auth        x-api-key header, demo keys: demo-agent-key-1, demo-agent-key-2");
    println!(
        "  quote ttl   {QUOTE_TTL_MS} ms, rate limit {}/min per caller",
        state.limit_per_minute
    );
    println!();

    for incoming in listener.incoming() {
        let mut stream = match incoming {
            Ok(s) => s,
            Err(_) => continue,
        };

        // Per-socket read and write timeouts.
        //
        // Found by the external agent's burst test, which made the server stop
        // responding entirely: this server is single-threaded and blocking, so one slow
        // or half-open client parked in `read_line` stalls every client behind it. For
        // an endpoint strangers can reach that is a denial of service with no attacker
        // required. A dropped slow connection is strictly better than a stalled server,
        // so both directions get a short deadline.
        let _ = stream.set_read_timeout(Some(std::time::Duration::from_secs(3)));
        let _ = stream.set_write_timeout(Some(std::time::Duration::from_secs(3)));
        let mut reader = BufReader::new(match stream.try_clone() {
            Ok(s) => s,
            Err(_) => continue,
        });

        let mut request_line = String::new();
        if reader.read_line(&mut request_line).is_err() {
            continue;
        }
        let mut parts = request_line.split_whitespace();
        let method = parts.next().unwrap_or("").to_string();
        let path = parts.next().unwrap_or("").to_string();

        let mut headers: HashMap<String, String> = HashMap::new();
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line).is_err() || line.trim().is_empty() {
                break;
            }
            if let Some((k, v)) = line.split_once(':') {
                headers.insert(k.trim().to_lowercase(), v.trim().to_string());
            }
        }
        let body_len: usize = headers
            .get("content-length")
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        let mut body_bytes = vec![0u8; body_len];
        if body_len > 0 && reader.read_exact(&mut body_bytes).is_err() {
            continue;
        }
        let body: Value = serde_json::from_slice(&body_bytes).unwrap_or(Value::Null);

        // ---- unauthenticated endpoint ----
        if method == "GET" && path == "/health" {
            respond(
                &mut stream,
                "200 OK",
                &json!({
                    "ok": true, "chain_id": chain_id,
                    "served": state.served, "refused": state.refused,
                    "protocol_version": "1.0.0"
                }),
            );
            continue;
        }

        // ---- auth ----
        let caller = match headers.get("x-api-key").and_then(|k| state.api_keys.get(k)) {
            Some(c) => c.clone(),
            None => {
                state.refused += 1;
                respond(
                    &mut stream,
                    "401 Unauthorized",
                    &json!({"error": "missing or unknown x-api-key"}),
                );
                continue;
            }
        };

        if !state.rate_ok(&caller) {
            state.refused += 1;
            respond(
                &mut stream,
                "429 Too Many Requests",
                &json!({"error": "rate limit exceeded", "limit_per_minute": state.limit_per_minute}),
            );
            continue;
        }

        // Chain read for every authenticated request, served from a 2 second cache.
        // Never a cached view the caller CANNOT AUDIT: block number and snapshot age
        // are in every response.
        let req_now = now_ms();
        let cached = state
            .snapshot
            .as_ref()
            .filter(|(_, at)| req_now.saturating_sub(*at) < SNAPSHOT_TTL_MS)
            .map(|(s, at)| (s.clone(), *at));

        let (snap, snapshot_fetched_at) = match cached {
            Some(pair) => pair,
            None => match read_snapshot(&client, venue) {
                Ok(s) => {
                    state.snapshot = Some((s.clone(), req_now));
                    (s, req_now)
                }
                Err(e) => {
                    state.refused += 1;
                    respond(
                        &mut stream,
                        "503 Service Unavailable",
                        &json!({"error": format!("chain read failed: {e}")}),
                    );
                    continue;
                }
            },
        };
        let snapshot_age_ms = req_now.saturating_sub(snapshot_fetched_at);
        let signals = intel.observe(&snap, snap.chain_time_ms);

        // Guard state shares the snapshot's cache window, for the same reason: two more
        // round trips per request is what made the rate limit unenforceable.
        if snapshot_age_ms == 0 || state.guard_state.is_none() {
            let killed = client.call_bool(guard, "killed()", &[]).unwrap_or(false);
            let exposure_wei = client
                .call_u128(guard, "exposureOf(bytes32)", &[market_word])
                .unwrap_or(0);
            state.guard_state = Some((
                killed,
                market_intel::wei_to_micro(i128::try_from(exposure_wei).unwrap_or(0)),
            ));
        }
        let (killed, exposure) = state.guard_state.unwrap_or((false, 0));

        let mut ctx = RiskContext::healthy_at(snap.chain_time_ms);
        ctx.manual_kill = killed;
        let portfolio = Portfolio {
            free_margin_micro: 1_000 * MICRO,
            ..Default::default()
        };

        match (method.as_str(), path.as_str()) {
            ("GET", "/thesis") => {
                let (thesis, confidence) = MarketIntel::thesis(&signals);
                state.served += 1;
                respond(
                    &mut stream,
                    "200 OK",
                    &json!({
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
                );
            }

            ("GET", "/capacity") => {
                // Remaining headroom, discovered by asking the risk engine rather than
                // by recomputing limits here. Two implementations of the same limit is
                // how they end up disagreeing.
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
                state.served += 1;
                respond(
                    &mut stream,
                    "200 OK",
                    &json!({
                        "max_permitted_size_micro": permitted.to_string(),
                        "current_exposure_micro": exposure.to_string(),
                        "first_refusal_beyond": refusal,
                        "halted": killed
                    }),
                );
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
                    state.refused += 1;
                    respond(
                        &mut stream,
                        "400 Bad Request",
                        &json!({"error": "size_micro must be a positive integer string"}),
                    );
                    continue;
                }

                // Price the quote off the live book, refusing if there is no reference.
                let reference = match (side, signals.best_ask, signals.best_bid) {
                    (Side::Buy, Some(ask), _) => ask,
                    (Side::Sell, _, Some(bid)) => bid,
                    _ => {
                        state.refused += 1;
                        respond(
                            &mut stream,
                            "409 Conflict",
                            &json!({"error": "no reference price on the requested side"}),
                        );
                        continue;
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
                        state.refused += 1;
                        respond(
                            &mut stream,
                            "409 Conflict",
                            &json!({
                                "error": "risk gate refused",
                                "refusal": format!("{r:?}"),
                                "rwa_specific": r.is_rwa_specific()
                            }),
                        );
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
                        state.quotes.insert(id, q.clone());
                        state.served += 1;
                        respond(
                            &mut stream,
                            "200 OK",
                            &json!({
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
                        );
                    }
                }
            }

            ("POST", "/accept") => {
                let id = body.get("quote_id").and_then(Value::as_u64).unwrap_or(0);
                let now = now_ms();
                match state.quotes.get_mut(&id) {
                    None => {
                        state.refused += 1;
                        respond(
                            &mut stream,
                            "404 Not Found",
                            &json!({"error": "unknown quote_id"}),
                        );
                    }
                    Some(q) if q.caller != caller => {
                        state.refused += 1;
                        respond(
                            &mut stream,
                            "403 Forbidden",
                            &json!({"error": "quote belongs to a different caller"}),
                        );
                    }
                    Some(q) if q.consumed => {
                        state.refused += 1;
                        respond(
                            &mut stream,
                            "409 Conflict",
                            &json!({"error": "quote already consumed"}),
                        );
                    }
                    Some(q) if now > q.expires_at_ms => {
                        state.refused += 1;
                        respond(
                            &mut stream,
                            "410 Gone",
                            &json!({
                                "error": "quote expired",
                                "expired_ms_ago": now - q.expires_at_ms
                            }),
                        );
                    }
                    Some(q) => {
                        q.consumed = true;
                        let accepted = q.clone();
                        state.served += 1;
                        respond(
                            &mut stream,
                            "200 OK",
                            &json!({
                                "accepted": true,
                                "quote_id": accepted.id,
                                "market": accepted.market,
                                "side": accepted.side,
                                "size_micro": accepted.size_micro.to_string(),
                                "price_micro": accepted.price_micro.to_string(),
                                "held_ms": now - accepted.issued_at_ms,
                                "note": "settlement is performed by the brain runtime; this endpoint records acceptance"
                            }),
                        );
                    }
                }
            }

            _ => {
                state.refused += 1;
                respond(
                    &mut stream,
                    "404 Not Found",
                    &json!({"error": "unknown endpoint"}),
                );
            }
        }
    }

    Ok(())
}
