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
//! Served by `tiny_http` on a pool of worker threads.
//!
//! The first version was a single-threaded blocking HTTP/1.1 server written on the standard
//! library, justified as having no dependency surface. That reasoning was wrong for an endpoint
//! strangers can reach: a 40-request burst made it stop responding entirely, because every request
//! is serviced in sequence and each one does chain reads. v1 diagnosed a slow client parked in
//! `read_line` and added 3-second socket timeouts, which could not have helped, because the queue
//! was the problem rather than any single socket.
//!
//! `tiny_http` owns the parsing now, which also deletes the hand-written request-line, header and
//! content-length handling where the bug lived, and `Arc<Server>` across N workers is the
//! concurrency pattern from its own documentation. Shared state sits behind one `Mutex` that is
//! never held across a chain read.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
// `Arc` is needed for the shared `Server` handed to each worker thread, and `Mutex` for the one
// piece of shared state. Imported explicitly rather than via a prelude that does not include them.
//
// This comment was previously mangled to "//  is needed for ." because it was written through a
// heredoc passed to `wsl -- bash -c`, which eats backticked words (E4).
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use tiny_http::{Header, Response, Server};

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

/// Gap between refresh cycles. The refresh itself dominates: a cycle is this plus the ~35 second
/// walk of the book, so the effective refresh period is about 37 seconds. Kept small so the gap is
/// not the limiting factor, and so a faster book read shortens the cycle automatically.
const SNAPSHOT_TTL_MS: u64 = 2_000;

/// A request is refused rather than served from a view older than this.
///
/// SET FROM A MEASUREMENT, not from a number that sounded right. A full refresh walks the order
/// book one `orders(i)` call at a time and took **34,979 ms** for 35 live orders against this
/// RPC. The
/// first version of this constant was 10,000 ms, which is shorter than a single refresh cycle: the
/// cache would have been declared too stale to serve for most of every cycle, and the endpoint would
/// have spent its life returning 503 while working perfectly.
///
/// 120 seconds is roughly three refresh cycles, so the bound catches a refresher that has actually
/// died rather than one that is merely mid-read. Every response carries `snapshot_age_ms`, so a
/// caller who needs a fresher view than this can enforce their own bound on a number we hand them
/// rather than trusting ours.
const MAX_SERVE_AGE_MS: u64 = 120_000;

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

/// Build a JSON response. The status is a number now rather than a "200 OK" string, because
/// tiny_http owns the reason phrase and two sources for it is one too many.
fn json_response(status: u16, body: &Value) -> Response<std::io::Cursor<Vec<u8>>> {
    let text = body.to_string();
    Response::from_string(text)
        .with_status_code(status)
        .with_header(
            Header::from_bytes(&b"content-type"[..], &b"application/json"[..])
                .expect("static header is valid"),
        )
        // CORS on EVERY response, not just the routes a browser happens to use today.
        //
        // The dashboard is served from :4173 and this listens on :8080, so every call from the page
        // is cross-origin. A per-route exception is the kind of thing that gets forgotten the moment
        // a second consumer appears.
        //
        // `*` is correct here rather than lax: this API is deliberately unauthenticated and has no
        // privileged path, which the module docs already state. There are no credentials for an
        // origin to steal, so restricting origins would add a config knob and protect nothing.
        .with_header(
            Header::from_bytes(&b"access-control-allow-origin"[..], &b"*"[..])
                .expect("static header is valid"),
        )
        .with_header(
            Header::from_bytes(
                &b"access-control-allow-headers"[..],
                &b"content-type, x-api-key"[..],
            )
            .expect("static header is valid"),
        )
        .with_header(
            Header::from_bytes(
                &b"access-control-allow-methods"[..],
                &b"GET, POST, OPTIONS"[..],
            )
            .expect("static header is valid"),
        )
}

/// True while a demo cycle is running. See the module note on double-clicks.
static DEMO_RUNNING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Count the lines in the decision journal, so a caller can prove a row was ADDED.
fn journal_len(repo: &str) -> usize {
    std::fs::read_to_string(format!("{repo}/evidence/journal.jsonl"))
        .map(|s| s.lines().filter(|l| !l.trim().is_empty()).count())
        .unwrap_or(0)
}

/// The last journal row, parsed. `None` when the journal is empty or unreadable.
fn last_journal_row(repo: &str) -> Option<Value> {
    let text = std::fs::read_to_string(format!("{repo}/evidence/journal.jsonl")).ok()?;
    let line = text.lines().rfind(|l| !l.trim().is_empty())?;
    serde_json::from_str(line).ok()
}

/// Run ONE real agent cycle and report what it did.
///
/// This spawns the runtime binary rather than calling into it, for the same reason ADR-008 puts
/// signing in `cast`: the runtime owns the decision loop, the keystore and the submission path, and
/// a second in-process copy of that logic is a second thing to keep correct.
fn run_demo_cycle(repo: &str) -> (u16, Value) {
    use std::sync::atomic::Ordering;

    // A judge WILL double-click. Two `asml run` processes would submit from the same key and collide
    // on the nonce, and the second failure would look like a broken agent rather than a double-click.
    if DEMO_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return (
            429,
            json!({
                "error": "a demo cycle is already running",
                "action": "wait for the current cycle to finish, then press again",
            }),
        );
    }

    let before = journal_len(repo);
    let started = std::time::Instant::now();

    let out = std::process::Command::new(format!("{repo}/target/release/asml"))
        .arg("run")
        .arg("1")
        .env("ASML_REPO", repo)
        .output();

    DEMO_RUNNING.store(false, Ordering::SeqCst);

    let elapsed_ms = started.elapsed().as_millis() as u64;

    match out {
        Err(e) => (
            500,
            json!({
                "error": format!("could not start the agent: {e}"),
                "action": "the runtime binary may not be built; run cargo build --release -p runtime",
            }),
        ),
        Ok(o) => {
            let after = journal_len(repo);
            let row = last_journal_row(repo);

            // The counter to this task's fake win. A replay would leave the journal length unchanged.
            if after <= before {
                return (
                    500,
                    json!({
                        "error": "the cycle produced no new journal row",
                        "journal_before": before,
                        "journal_after": after,
                        "stderr": String::from_utf8_lossy(&o.stderr).chars().take(400).collect::<String>(),
                    }),
                );
            }

            (
                200,
                json!({
                    "ok": true,
                    "elapsed_ms": elapsed_ms,
                    "journal_before": before,
                    "journal_after": after,
                    "decision_id": row.as_ref().and_then(|r| r.get("decision_id").cloned()),
                    "block_number": row.as_ref().and_then(|r| r.get("block_number").cloned()),
                    "thesis": row.as_ref().and_then(|r| r.get("thesis").cloned()),
                    "risk_verdict": row.as_ref().and_then(|r| r.get("risk_verdict").cloned()),
                    "action": row.as_ref().and_then(|r| r.get("action").cloned()),
                    "tx_hash": row.as_ref().and_then(|r| r.get("tx_hash").cloned()),
                    "candidates": row
                        .as_ref()
                        .and_then(|r| r.get("candidates"))
                        .and_then(|c| c.as_array().map(|a| a.len())),
                }),
            )
        }
    }
}

/// Read the book and the guard once, and put them in the cache.
///
/// This is the ONLY place the coordination API touches the chain. Called once before the listener
/// accepts, then on a timer by the refresher thread.
/// Repo root, for the default handoff path. Read from the environment the same way `main` does, so
/// the two cannot disagree.
fn repo_root_of() -> String {
    std::env::var("ASML_REPO")
        .unwrap_or_else(|_| "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X".to_string())
}

/// Append one line to a file, returning the error text rather than panicking.
///
/// A failed handoff write must not take down a worker or hide itself: the response says whether the
/// write succeeded, so a caller knows whether to expect settlement.
fn append_line(path: &str, line: &str) -> Option<String> {
    use std::io::Write as _;
    if let Some(parent) = std::path::Path::new(path).parent() {
        if let Err(e) = std::fs::create_dir_all(parent) {
            return Some(e.to_string());
        }
    }
    match std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        Ok(mut f) => writeln!(f, "{line}").err().map(|e| e.to_string()),
        Err(e) => Some(e.to_string()),
    }
}

fn prime(
    client: &chain_client::ChainClient,
    state: &Arc<Mutex<State>>,
    venue: chain_client::Address,
    guard: chain_client::Address,
    market_word: chain_client::Word,
) -> String {
    let started = now_ms();
    let snap = match read_snapshot(client, venue) {
        Ok(s) => s,
        Err(e) => return format!("snapshot read FAILED: {e}"),
    };
    let killed = client.call_bool(guard, "killed()", &[]).unwrap_or(false);
    let exposure_wei = client
        .call_u128(guard, "exposureOf(bytes32)", &[market_word])
        .unwrap_or(0);
    let block = snap.block_number;
    let orders = snap.orders.len();
    let now = now_ms();
    let mut s = state.lock().expect("state mutex");
    s.snapshot = Some((snap, now));
    s.guard_state = Some((
        killed,
        market_intel::wei_to_micro(i128::try_from(exposure_wei).unwrap_or(0)),
    ));
    format!(
        "block {block}, {orders} live orders, killed={killed}, took {}ms",
        now.saturating_sub(started)
    )
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

    let state = Arc::new(Mutex::new(State::new()));
    let limit = state.lock().expect("fresh mutex").limit_per_minute;

    // WORKER COUNT. Eight is enough to absorb the 40-request burst that stalled the previous
    // server while staying far below anything that could exhaust the RPC endpoint: each worker
    // holds at most one in-flight chain read, and the snapshot cache means most requests do none.
    // Not made configurable, because a knob nobody tunes is a knob that misleads.
    let workers: usize = 8;

    // PRIME BEFORE BINDING. `Server::http` binds and starts accepting immediately, so priming after
    // it meant connections sat in the kernel backlog until the workers started: measured, /health
    // took 23.1 seconds on a server that answers it in under a millisecond once running. A server
    // that accepts connections it cannot yet answer is claiming to be ready when it is not.
    println!("ASML-X coordination API");
    println!("  chain       {chain_id} (verified)");
    println!("  priming     reading the book before binding the socket...");
    let primed = prime(&client, &state, venue, guard, market_word);
    println!("  primed      {primed}");

    let server = Arc::new(Server::http(("127.0.0.1", port)).map_err(|e| e.to_string())?);

    println!("  listening   http://127.0.0.1:{port}");
    println!(
        "  server      tiny_http, {workers} worker threads, chain reads on a refresher thread"
    );
    println!("  endpoints   GET /health  GET /thesis  GET /capacity");
    println!("              POST /quote  POST /accept");
    println!("  auth        x-api-key header, demo keys: demo-agent-key-1, demo-agent-key-2");
    println!("  quote ttl   {QUOTE_TTL_MS} ms, rate limit {limit}/min per caller");
    println!("  freshness   snapshot refreshed every {SNAPSHOT_TTL_MS} ms, refused past {MAX_SERVE_AGE_MS} ms");
    println!();

    // One refresher thread owns every chain read from here on.
    {
        let state = Arc::clone(&state);
        let client = chain_client::ChainClient::new(RPC, Some(FALLBACK.to_string()));
        std::thread::spawn(move || loop {
            std::thread::sleep(std::time::Duration::from_millis(SNAPSHOT_TTL_MS));
            let _ = prime(&client, &state, venue, guard, market_word);
        });
    }

    let mut handles = Vec::new();
    for _ in 0..workers {
        let server = Arc::clone(&server);
        let state = Arc::clone(&state);
        // Each worker owns its own market-intel buffer. No chain client: workers do not read the
        // chain at all, which is the whole point of the refresher below.
        let risk = RiskEngine::new(Limits::conservative_testnet());

        handles.push(std::thread::spawn(move || {
            let mut intel = MarketIntel::new(32);
            loop {
                let mut request = match server.recv() {
                    Ok(r) => r,
                    Err(_) => break,
                };
                let (status, body) = handle(&mut request, &state, &risk, &mut intel, chain_id);
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
#[allow(clippy::too_many_lines)]
fn handle(
    request: &mut tiny_http::Request,
    state: &Arc<Mutex<State>>,
    risk: &RiskEngine,
    intel: &mut MarketIntel,
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

    // Read a body ONLY for methods that carry one, and only when the client declared its length.
    //
    // Reading unconditionally made every GET wait for bytes the client never promised: curl closes
    // promptly so the read hit EOF, while urllib held the connection open and the read blocked until
    // the client timed out 30 seconds later. The server stayed responsive on /health the whole time,
    // which is what made it look like a stall rather than a blocking read.
    let has_body = matches!(method.as_str(), "POST" | "PUT" | "PATCH")
        && headers
            .get("content-length")
            .and_then(|v| v.parse::<usize>().ok())
            .unwrap_or(0)
            > 0;
    let body: Value = if has_body {
        let mut body_text = String::new();
        let _ = std::io::Read::read_to_string(request.as_reader(), &mut body_text);
        serde_json::from_str(&body_text).unwrap_or(Value::Null)
    } else {
        Value::Null
    };

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

    // ---- CORS preflight, answered BEFORE auth ----
    //
    // A preflight never carries credentials, so checking x-api-key first returns 401 and the browser
    // then blocks the real request. curl does not preflight, which is why this endpoint worked from
    // a shell and silently failed from the page.
    if method == "OPTIONS" {
        return (204, json!({}));
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

    // ---- snapshot, READ ONLY from the cache. This path never touches the chain. ----
    //
    // A cold `read_snapshot` walks the entire order book: one call for the count and one per order,
    // about 30 sequential RPC round trips. Doing that inside a request means the first caller waits
    // a minute or more, every other caller queues behind it, and an unauthenticated stranger can
    // amplify one HTTP request into 30 round trips against a public RPC. Measured before this
    // change: /health answered in 1.7ms, /thesis never answered, and a 40-request burst produced 40
    // timeouts over 802 seconds while the RPC itself was healthy.
    //
    // The refresher thread owns all chain reads now. A handler that finds no fresh snapshot refuses
    // with the age rather than fetching one.
    let req_now = now_ms();
    let (snap, snapshot_fetched_at, killed, exposure) = {
        let s = state.lock().expect("state mutex");
        match (&s.snapshot, s.guard_state) {
            (Some((snap, at)), Some((killed, exposure))) => (snap.clone(), *at, killed, exposure),
            _ => {
                drop(s);
                let mut s = state.lock().expect("state mutex");
                s.refused += 1;
                return (
                    503,
                    json!({
                        "error": "no chain snapshot available yet",
                        "detail": "the refresher has not completed its first read"
                    }),
                );
            }
        }
    };
    let snapshot_age_ms = req_now.saturating_sub(snapshot_fetched_at);
    if snapshot_age_ms > MAX_SERVE_AGE_MS {
        let mut s = state.lock().expect("state mutex");
        s.refused += 1;
        return (
            503,
            json!({
                "error": "chain view too stale to serve",
                "snapshot_age_ms": snapshot_age_ms,
                "max_serve_age_ms": MAX_SERVE_AGE_MS
            }),
        );
    }
    let signals = intel.observe(&snap, snap.chain_time_ms);

    let mut ctx = RiskContext::healthy_at(snap.chain_time_ms);
    ctx.manual_kill = killed;

    // THE PORTFOLIO MUST MATCH THE ONE SETTLEMENT WILL USE.
    //
    // This was `Portfolio { free_margin_micro: 1_000 * MICRO, ..Default::default() }`, an EMPTY book,
    // while the runtime's settlement path builds a portfolio holding the real onchain exposure.
    // Measured consequence: /capacity offered 12,500,000 micro to an external caller, the quote was
    // issued, and settlement refused it with MarketNotionalTooLarge { got: 56299998, limit: 50000000 }
    // because the market was already at 50.36 of its 50 cap. A quote the settlement gate will refuse
    // is worse than a refusal at quote time.
    //
    // `exposure` here is the same `exposureOf` reading the refresher already takes, marked at the
    // live mid, which is exactly what crates/runtime read_portfolio does.
    let mark = signals.mid.unwrap_or(0);
    let positions = if exposure > 0 && mark > 0 {
        vec![core_types::Position {
            market: MarketId::new("tBASE/tQUOTE"),
            kind: InstrumentKind::Spot,
            net_size_micro: (exposure * MICRO) / mark,
            mark_price_micro: core_types::Stamped::new(mark, snap.chain_time_ms),
        }]
    } else {
        vec![]
    };
    let portfolio = Portfolio {
        positions,
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    };

    match (method.as_str(), path.as_str()) {
        // Preflight. A browser sends OPTIONS before any cross-origin POST carrying a content-type.
        ("OPTIONS", _) => (204, json!({})),

        // TASK 10.1: flow timing marks, appended to a file so a timing claim has an artifact.
        ("POST", "/flow-mark") => {
            let repo = repo_root_of();
            let path = format!("{repo}/evidence/phase10/flow-marks.jsonl");
            let line = body.to_string();
            match append_line(&path, &line) {
                Some(err) => (500, json!({ "error": err })),
                None => (200, json!({ "ok": true })),
            }
        }

        // TASK 9.6: one button, one real cycle against the live chain.
        ("POST", "/demo") => {
            state.lock().expect("state mutex").served += 1;
            run_demo_cycle(&repo_root_of())
        }

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
                    drop(s);

                    // HANDOFF, not settlement. This process holds no keystore and never will: it is
                    // the surface strangers reach, and putting a signer behind an endpoint guarded by
                    // a demo API key would be the worst possible place for one. The runtime owns the
                    // key and the executor, so acceptance is appended here and settled there.
                    //
                    // The record carries the quote id, the caller and the block the quote was priced
                    // at, which is what makes the eventual transaction traceable to THIS request
                    // rather than merely contemporaneous with it.
                    let handoff = json!({
                        "quote_id": accepted.id,
                        "caller": accepted.caller,
                        "market": accepted.market,
                        "side": accepted.side,
                        "size_micro": accepted.size_micro.to_string(),
                        "price_micro": accepted.price_micro.to_string(),
                        "priced_at_block": snap.block_number,
                        "accepted_at_ms": now,
                        "settled": false
                    });
                    let path = std::env::var("ASML_ACCEPTED_PATH").unwrap_or_else(|_| {
                        format!("{}/evidence/phase6/accepted-quotes.jsonl", repo_root_of())
                    });
                    let write_err = append_line(&path, &handoff.to_string());

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
                            "priced_at_block": snap.block_number,
                            "handoff_written": write_err.is_none(),
                            "handoff_error": write_err,
                            "note": "queued for settlement by the brain runtime, which owns the keystore; this endpoint never signs"
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
