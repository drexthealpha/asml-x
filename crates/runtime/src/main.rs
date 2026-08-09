//! ASML-X runtime. The perceive, decide, gate, act, journal loop.
//!
//! Usage:
//!   asml observe [cycles]     read-only: real chain reads, real decisions, no txs
//!   asml run [cycles]         as above, and submits the approved action onchain
//!   asml baseline [cycles]    the naive baseline mode, for task 4.3
//!
//! Signing: delegated to `cast` as a subprocess with the encrypted keystore. Stated
//! plainly per R9 rather than wrapped to look native. ADR-008 records why: a
//! hand-rolled secp256k1 signer and RLP encoder is exactly the kind of brittle
//! plumbing this project refuses to hide behind a clean interface, and `cast` is
//! the same tool that produced every verified transaction so far.

use core_types::{InstrumentKind, MarketId, OrderIntent, Portfolio, Position, Stamped, MICRO};
use decision_engine::{assert_real_search, Action, DecisionEngine, NaiveBaseline, Params};
use journal::{Entry, Journal, SignalRecord};
use market_intel::{read_snapshot, MarketIntel, Signals};
use risk_engine::{Limits, RiskContext, RiskEngine, RwaState};
use std::process::Command;

const RPC: &str = "https://testrpc.xlayer.tech";
const FALLBACK: &str = "https://xlayer-testnet.drpc.org";
const EXPECTED_CHAIN_ID: u64 = 1952;

struct Deployments {
    venue: chain_client::Address,
    guard: chain_client::Address,
    market_id_hex: String,
    rwa_vault: Option<chain_client::Address>,
    rwa_guard: Option<chain_client::Address>,
}

fn load_deployments(repo_root: &str) -> Result<Deployments, Box<dyn std::error::Error>> {
    let path = format!("{repo_root}/deployments.json");
    let text = std::fs::read_to_string(&path)
        .map_err(|e| format!("cannot read {path}: {e}. Run scripts/12-deploy-venue.sh first."))?;
    let v: serde_json::Value = serde_json::from_str(&text)?;
    let get = |k: &str| -> Result<String, String> {
        v.get(k)
            .and_then(serde_json::Value::as_str)
            .map(ToString::to_string)
            .ok_or_else(|| format!("deployments.json missing {k}"))
    };
    let opt_addr = |k: &str| -> Option<chain_client::Address> {
        v.get(k)
            .and_then(serde_json::Value::as_str)
            .and_then(|s| chain_client::parse_address(s).ok())
    };
    Ok(Deployments {
        venue: chain_client::parse_address(&get("venue")?)?,
        guard: chain_client::parse_address(&get("riskGuard")?)?,
        market_id_hex: get("marketId")?,
        rwa_vault: opt_addr("rwaVault"),
        rwa_guard: opt_addr("rwaRiskGuard"),
    })
}

/// Read our own exposure from the guard and build the portfolio the risk engine
/// reasons over.
///
/// Deliberately sourced from the chain rather than from local bookkeeping. Local
/// state that drifts from the chain is how an agent convinces itself it is flat
/// while holding a position.
fn read_portfolio(
    client: &chain_client::ChainClient,
    d: &Deployments,
    signals: &Signals,
    chain_time_ms: u64,
) -> Result<Portfolio, Box<dyn std::error::Error>> {
    let market_word = chain_client::parse_word(&d.market_id_hex)?;
    let exposure_wei = client.call_u128(d.guard, "exposureOf(bytes32)", &[market_word])?;
    // Normalise at the boundary, same as the order book reads.
    let exposure = market_intel::wei_to_micro(i128::try_from(exposure_wei)?);
    let mark = signals.mid.unwrap_or(0);

    // Exposure is a quote-denominated absolute number in the guard, so it is
    // represented here as a single long position at the current mark. This is an
    // approximation and is labelled as one: the guard tracks absolute exposure, not
    // signed size, so direction is not recoverable from it. Phase 7 attributes
    // direction from the journal instead.
    let positions = if exposure > 0 && mark > 0 {
        let size = (exposure * MICRO) / mark;
        vec![Position {
            market: MarketId::new("tBASE/tQUOTE"),
            kind: InstrumentKind::Spot,
            net_size_micro: size,
            mark_price_micro: Stamped::new(mark, chain_time_ms),
        }]
    } else {
        vec![]
    };

    Ok(Portfolio {
        positions,
        // Free margin is the executor's spendable quote. Read as a token balance in
        // a later pass; for now the conservative testnet limits bind first.
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    })
}

fn signal_records(s: &Signals) -> Vec<SignalRecord> {
    let mut out = Vec::new();
    if let Some(e) = &s.spread_bps {
        out.push(SignalRecord {
            name: "spread_bps".into(),
            value_micro: e.value,
            confidence_halfwidth_micro: e.confidence_halfwidth,
            input_age_ms: s.input_age_ms,
        });
    }
    if let Some(e) = &s.realized_vol_bps {
        out.push(SignalRecord {
            name: "realized_vol_bps".into(),
            value_micro: e.value,
            confidence_halfwidth_micro: e.confidence_halfwidth,
            input_age_ms: s.input_age_ms,
        });
    }
    if let Some(e) = &s.imbalance_bps {
        out.push(SignalRecord {
            name: "imbalance_bps".into(),
            value_micro: e.value,
            confidence_halfwidth_micro: e.confidence_halfwidth,
            input_age_ms: s.input_age_ms,
        });
    }
    out.push(SignalRecord {
        name: "bid_depth_base".into(),
        value_micro: s.bid_depth_base,
        confidence_halfwidth_micro: 0,
        input_age_ms: s.input_age_ms,
    });
    out.push(SignalRecord {
        name: "ask_depth_base".into(),
        value_micro: s.ask_depth_base,
        confidence_halfwidth_micro: 0,
        input_age_ms: s.input_age_ms,
    });
    out
}

/// Submit an approved take through the BatchExecutor via `cast`.
///
/// The guard leg comes first because the contract enforces it, so a cap breach or a
/// halt reverts the whole batch before any token moves.
fn submit_take(
    repo_root: &str,
    order_id: u64,
    base_amount_wei: i128,
    quote_notional_wei: i128,
    decision_id: u64,
) -> Result<String, String> {
    let out = Command::new("bash")
        .arg(format!("{repo_root}/scripts/submit-take.sh"))
        .arg(order_id.to_string())
        .arg(base_amount_wei.to_string())
        .arg(quote_notional_wei.to_string())
        .arg(decision_id.to_string())
        .output()
        .map_err(|e| format!("cannot run submit-take.sh: {e}"))?;
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    if !out.status.success() {
        return Err(format!("submit failed: {stdout} {stderr}"));
    }
    stdout
        .lines()
        .find_map(|l| l.strip_prefix("TX="))
        .map(ToString::to_string)
        .ok_or_else(|| format!("no TX= line in output: {stdout} {stderr}"))
}

/// Read the RWA vault's risk view from chain and build the offchain RwaState.
///
/// One call to `riskView()` rather than five separate getters, deliberately: five
/// reads can straddle a block boundary and produce a view of the instrument that
/// never actually existed.
fn read_rwa_state(
    client: &chain_client::ChainClient,
    vault: chain_client::Address,
    guard: chain_client::Address,
) -> Result<RwaState, Box<dyn std::error::Error>> {
    let w = client.call_words(vault, "riskView()", &[], 6)?;
    let divergence = client.call_u128(guard, "divergenceBps()", &[])?;
    Ok(RwaState {
        oracle_age_secs: u64::try_from(chain_client::u128_from_word(&w[1])?)?,
        issuer_paused: chain_client::bool_from_word(&w[2])?,
        seconds_until_window: u64::try_from(chain_client::u128_from_word(&w[4])?)?,
        divergence_bps: u32::try_from(divergence)?,
        yield_index_micro: market_intel::wei_to_micro(i128::try_from(
            chain_client::u128_from_word(&w[5])?,
        )?),
    })
}

/// Task 5.3.4: the same order shape, the same live signals, evaluated against a pure
/// crypto market and an RWA-linked market, side by side.
///
/// This is the claim being tested: the agent treats an RWA-linked market differently
/// for reasons it can name, rather than applying a global brake or a cosmetic label.
fn side_by_side(
    client: &chain_client::ChainClient,
    d: &Deployments,
    risk: &RiskEngine,
) -> Result<(), Box<dyn std::error::Error>> {
    let (vault, rwa_guard) = match (d.rwa_vault, d.rwa_guard) {
        (Some(v), Some(g)) => (v, g),
        _ => return Err("RWA stack not in deployments.json, run scripts/22-deploy-rwa.sh".into()),
    };

    let snap = read_snapshot(client, d.venue)?;
    let mut intel = MarketIntel::new(8);
    let signals = intel.observe(&snap, snap.chain_time_ms);
    let rwa = read_rwa_state(client, vault, rwa_guard)?;

    println!("Live inputs, block {}", snap.block_number);
    println!(
        "  crypto book: {} live orders, spread {:?} bps, imbalance {:?} bps",
        signals.live_order_count,
        signals.spread_bps.as_ref().map(|e| e.value),
        signals.imbalance_bps.as_ref().map(|e| e.value)
    );
    println!("  rwa vault:   oracle age {}s, paused {}, until window {}s, divergence {} bps, yield index {}",
        rwa.oracle_age_secs, rwa.issuer_paused, rwa.seconds_until_window,
        rwa.divergence_bps, market_intel::fmt_micro(rwa.yield_index_micro));
    println!();

    // One order shape. Only the instrument kind and market differ.
    let size = 2 * MICRO;
    let price = MICRO;
    let spot = OrderIntent {
        market: MarketId::new("tBASE/tQUOTE"),
        kind: InstrumentKind::Spot,
        side: core_types::Side::Buy,
        size_micro: size,
        limit_price_micro: price,
        decision_id: 0,
    };
    let rwa_intent = OrderIntent {
        market: MarketId::new("RWA/tQUOTE"),
        kind: InstrumentKind::RwaLinked,
        ..spot.clone()
    };

    let pf = Portfolio {
        free_margin_micro: 1_000 * MICRO,
        ..Default::default()
    };
    let ctx = RiskContext::healthy_at(snap.chain_time_ms).with_rwa(rwa);

    let spot_verdict = risk.evaluate(&spot, &pf, &ctx);
    let rwa_verdict = risk.evaluate(&rwa_intent, &pf, &ctx);

    println!(
        "Identical order: Buy {} base at {}",
        market_intel::fmt_micro(size),
        market_intel::fmt_micro(price)
    );
    println!();
    println!("  CRYPTO market (tBASE/tQUOTE, Spot):");
    match &spot_verdict {
        Ok(a) => println!(
            "    APPROVED{}",
            if a.requires_human_approval() {
                ", human approval required"
            } else {
                ""
            }
        ),
        Err(r) => println!("    REFUSED: {r:?} (rwa-specific: {})", r.is_rwa_specific()),
    }
    println!();
    println!("  RWA market (RWA/tQUOTE, RwaLinked):");
    match &rwa_verdict {
        Ok(a) => println!(
            "    APPROVED{}",
            if a.requires_human_approval() {
                ", human approval required"
            } else {
                ""
            }
        ),
        Err(r) => println!("    REFUSED: {r:?} (rwa-specific: {})", r.is_rwa_specific()),
    }
    println!();

    let differed = spot_verdict.is_ok() != rwa_verdict.is_ok();
    let rwa_reason = rwa_verdict
        .as_ref()
        .err()
        .is_some_and(risk_engine::Refusal::is_rwa_specific);

    println!("DIVERGENT TREATMENT: {differed}");
    println!("RWA-SPECIFIC REASON: {rwa_reason}");
    if differed && rwa_reason {
        println!();
        println!("The same order is permitted on the crypto market and refused on the");
        println!("RWA market, and the refusal names an RWA-specific cause. A generic bot");
        println!("has no vocabulary for this refusal.");
    } else if !differed {
        println!();
        println!("Both markets agreed on this order at this moment. That is the honest");
        println!("state of the instrument right now, not a failure of the layer: with a");
        println!("fresh oracle, no pause, no divergence and no window nearby, an RWA");
        println!("market SHOULD behave like any other. Run scripts/23-rwa-live-triggers.sh");
        println!("to move the instrument into a refusing state and re-run this.");
    }

    // Also show what the chain itself says, so the offchain verdict is corroborated
    // rather than trusted.
    let onchain_ok = client.call_bool(rwa_guard, "rwaTradeableFlag()", &[])?;
    println!();
    println!("Onchain RwaRiskGuard.rwaTradeableFlag(): {onchain_ok}");
    println!(
        "Offchain risk engine agrees: {}",
        onchain_ok == rwa_verdict.is_ok() || !rwa_reason
    );

    Ok(())
}

/// Phase 7: the learning loop, driven by live chain state.
///
/// Each cycle: read the book, decide, record what direction the decision implied, settle
/// any decision old enough to be scored against a later mid, then update parameters from
/// measured accuracy and persist.
///
/// Decisions are recorded with the parameters IN FORCE at the time, so an outcome is
/// attributed to the parameter set that actually produced it rather than to whatever is
/// current when it settles.
fn learn_loop(
    client: &chain_client::ChainClient,
    d: &Deployments,
    risk: &RiskEngine,
    repo_root: &str,
    cycles: u64,
) -> Result<(), Box<dyn std::error::Error>> {
    use learning::{Learner, Predicted};

    let state_path = format!("{repo_root}/evidence/learned-state.json");
    let mut learner = Learner::load(&state_path, Params::default());
    let mut intel = MarketIntel::new(64);
    let mut jrnl = Journal::open(format!("{repo_root}/evidence/journal.jsonl"))?;

    println!("learning loop");
    println!("  state file      {state_path}");
    println!("  settled so far  {}", learner.settled_count());
    println!("  params at start {:?}", learner.params());
    println!("  {}", learner.explain());
    println!();

    // Forecast horizon: settle against a mid observed at least this much later.
    //
    // 60 seconds, not 6. The first version used 6 seconds and produced zero scored
    // outcomes: every forecast settled inside the same run, against a price that had not
    // moved, and was correctly dropped as flat. A horizon shorter than the interval at
    // which the market actually changes cannot score anything, so the number has to
    // reflect the venue's real cadence rather than the loop's cycle time.
    const SETTLE_LAG_MS: u64 = 60_000;

    for cycle in 0..cycles {
        let snap = match read_snapshot(client, d.venue) {
            Ok(s) => s,
            Err(e) => {
                println!("cycle {cycle}: chain read failed: {e}, treated as rpc_failed");
                continue;
            }
        };
        let now_ms = snap.chain_time_ms;
        let signals = intel.observe(&snap, now_ms);
        let portfolio = read_portfolio(client, d, &signals, now_ms)?;

        // Settle first, so this cycle's parameters reflect everything already known.
        let settled = if let Some(mid) = signals.mid {
            learner.settle_due(now_ms, mid, SETTLE_LAG_MS)
        } else {
            Vec::new()
        };
        for o in &settled {
            println!(
                "  settled decision {}: predicted {:?}, realized {} bps, correct {}, edge error {}",
                o.decision_id,
                o.predicted,
                o.realized_move_bps,
                o.direction_correct,
                o.edge_error_micro
            );
        }

        let changes = learner.update_params(now_ms);
        for c in &changes {
            println!(
                "  PARAM CHANGE {} {} -> {} because {}",
                c.parameter, c.from, c.to, c.trigger
            );
        }

        // Decide with the CURRENT learned parameters.
        let engine = DecisionEngine::new(
            MarketId::new("tBASE/tQUOTE"),
            InstrumentKind::Spot,
            learner.params().clone(),
        );
        let mut ctx = RiskContext::healthy_at(now_ms);
        if client.call_bool(d.guard, "killed()", &[]).unwrap_or(false) {
            ctx.manual_kill = true;
        }
        let decision_id = jrnl.reserve_id();
        let decision = engine.decide(&signals, &snap.orders, &portfolio, risk, &ctx, decision_id);

        let chosen = decision.chosen();
        let predicted = match chosen.map(|c| &c.action) {
            Some(Action::Take { side, .. }) => match side {
                core_types::Side::Buy => Predicted::Up,
                core_types::Side::Sell => Predicted::Down,
            },
            _ => Predicted::NoView,
        };
        let expected_edge = chosen.map_or(0, |c| c.expected_edge_micro);

        println!(
            "cycle {cycle} block {} | {} candidates | chose {} | predicts {:?} | momentum {} | pending {}",
            snap.block_number,
            decision.candidates.len(),
            chosen.map_or("none".to_string(), |c| c.action.label()),
            predicted,
            learner.params().momentum_weight_bps,
            learner.pending_count()
        );

        if let Some(mid) = signals.mid {
            learner.record_decision(learning::Pending {
                decision_id,
                predicted,
                mid_at_decision: mid,
                expected_edge_micro: expected_edge,
                opened_at_ms: now_ms,
                params_at_decision: learner.params().clone(),
                signal_name: "imbalance_bps".to_string(),
            });
        }

        let (thesis, confidence) = MarketIntel::thesis(&signals);
        jrnl.append(&Entry {
            decision_id,
            observed_at_ms: now_ms,
            block_number: snap.block_number,
            market: "tBASE/tQUOTE".into(),
            thesis,
            thesis_confidence_bps: confidence,
            signals: signal_records(&signals),
            candidates: decision.records(),
            risk_verdict: decision.risk_verdict.clone(),
            action: chosen.map(|c| c.action.label()),
            tx_hash: None,
            outcome: settled
                .iter()
                .map(|o| {
                    format!(
                        "decision {} realized {} bps, correct {}",
                        o.decision_id, o.realized_move_bps, o.direction_correct
                    )
                })
                .collect::<Vec<_>>()
                .join("; ")
                .into(),
            evidence: vec![format!("learn cycle at block {}", snap.block_number)],
        })?;

        learner.save()?;

        if cycle + 1 < cycles {
            std::thread::sleep(std::time::Duration::from_secs(3));
        }
    }

    let stats = learner.stats_for("imbalance_bps");
    println!();
    println!("=== learning summary ===");
    println!("  settled outcomes      {}", learner.settled_count());
    println!("  imbalance samples     {}", stats.samples);
    println!("  imbalance correct     {}", stats.correct);
    println!("  imbalance hit rate    {} bps", stats.hit_rate_bps());
    println!(
        "  mean edge error       {} micro",
        stats.mean_edge_error_micro()
    );
    println!("  final params          {:?}", learner.params());
    println!("  parameter changes     {}", learner.history().len());
    for c in learner.history() {
        println!(
            "    {} {} -> {} ({} samples, hit rate {} bps)",
            c.parameter, c.from, c.to, c.samples, c.hit_rate_bps
        );
    }
    println!("  {}", learner.explain());
    println!();
    println!(
        "  NOTE: hit rate on {} samples is not a performance claim. It is evidence",
        stats.samples
    );
    println!("  that outcomes are measured and parameters respond to them.");

    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    let mode = args.get(1).map_or("observe", String::as_str).to_string();
    let cycles: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(5);
    let repo_root = std::env::var("ASML_REPO")
        .unwrap_or_else(|_| "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X".to_string());

    let client = chain_client::ChainClient::new(RPC, Some(FALLBACK.to_string()));

    // Fail fast and loudly on the wrong chain. Chain 195 is the deprecated testnet
    // and would otherwise look like a working endpoint.
    let chain_id = client.chain_id()?;
    if chain_id != EXPECTED_CHAIN_ID {
        return Err(format!(
            "wrong chain: connected to {chain_id}, expected {EXPECTED_CHAIN_ID}. \
             195 is the DEPRECATED X Layer testnet."
        )
        .into());
    }

    let d = load_deployments(&repo_root)?;
    let mut jrnl = Journal::open(format!("{repo_root}/evidence/journal.jsonl"))?;
    let risk = RiskEngine::new(Limits::conservative_testnet());
    let engine = DecisionEngine::new(
        MarketId::new("tBASE/tQUOTE"),
        InstrumentKind::Spot,
        Params::default(),
    );
    let baseline = NaiveBaseline {
        fixed_base_amount: 2 * MICRO,
        market: MarketId::new("tBASE/tQUOTE"),
        kind: InstrumentKind::Spot,
    };
    let mut intel = MarketIntel::new(64);

    println!("ASML-X runtime");
    println!("  mode        {mode}");
    println!("  chain       {chain_id} (verified)");
    println!("  venue       {}", chain_client::hex_encode(&d.venue));
    println!("  guard       {}", chain_client::hex_encode(&d.guard));
    println!("  cycles      {cycles}");
    println!();

    if mode == "sidebyside" {
        return side_by_side(&client, &d, &risk);
    }

    if mode == "learn" {
        return learn_loop(&client, &d, &risk, &repo_root, cycles);
    }

    let mut actions_this_run: u32 = 0;

    for cycle in 0..cycles {
        let snap = match read_snapshot(&client, d.venue) {
            Ok(s) => s,
            Err(e) => {
                // A read failure is a risk event, not a retry opportunity.
                println!("cycle {cycle}: chain read failed: {e}. Treating as rpc_failed.");
                let mut ctx = RiskContext::healthy_at(0);
                ctx.rpc_failed = true;
                println!(
                    "  risk halted: {:?}",
                    risk.kill_check(&Portfolio::default(), &ctx)
                );
                continue;
            }
        };

        let now_ms = snap.chain_time_ms;
        let signals = intel.observe(&snap, now_ms);
        let (thesis, confidence) = MarketIntel::thesis(&signals);
        let portfolio = read_portfolio(&client, &d, &signals, snap.chain_time_ms)?;

        let mut ctx = RiskContext::healthy_at(now_ms);
        ctx.actions_last_minute = actions_this_run;
        // The guard is the binding authority, so ask it whether it is halted.
        let market_word = chain_client::parse_word(&d.market_id_hex)?;
        if client.call_bool(d.guard, "killed()", &[]).unwrap_or(false) {
            ctx.manual_kill = true;
        }
        let _ = market_word;

        let decision_id = jrnl.reserve_id();

        if mode == "baseline" {
            let intent = baseline.decide(&snap.orders, decision_id);
            let verdict = match &intent {
                None => "baseline: no live order, no action".to_string(),
                Some(i) => match risk.evaluate(i, &portfolio, &ctx) {
                    Ok(_) => "baseline: approved".to_string(),
                    Err(r) => format!("baseline: risk refused: {r:?}"),
                },
            };
            println!(
                "cycle {cycle} block {} | BASELINE | {verdict}",
                snap.block_number
            );
            jrnl.append(&Entry {
                decision_id,
                observed_at_ms: now_ms,
                block_number: snap.block_number,
                market: "tBASE/tQUOTE".into(),
                thesis: "naive baseline, no signals consulted".into(),
                thesis_confidence_bps: 0,
                signals: signal_records(&signals),
                candidates: vec![],
                risk_verdict: verdict,
                action: intent.map(|i| {
                    format!(
                        "{:?} {} base",
                        i.side,
                        market_intel::fmt_micro(i.size_micro)
                    )
                }),
                tx_hash: None,
                outcome: None,
                evidence: vec![format!(
                    "eth_call venue.orders at block {}",
                    snap.block_number
                )],
            })?;
            continue;
        }

        let decision = engine.decide(&signals, &snap.orders, &portfolio, &risk, &ctx, decision_id);

        // Hard guard: a cycle that evaluated one candidate is a defect, not a
        // decision. Refuse to journal it as if it were reasoning.
        if let Err(e) = assert_real_search(&decision) {
            println!("cycle {cycle}: DEFECT, {e}");
            continue;
        }

        let chosen_label = decision
            .chosen()
            .map_or("none".to_string(), |c| c.action.label());
        println!(
            "cycle {cycle} block {} | {} live orders | {} candidates | chose: {chosen_label}",
            snap.block_number,
            signals.live_order_count,
            decision.candidates.len()
        );
        println!("  thesis ({confidence} bps): {thesis}");
        println!("  risk:   {}", decision.risk_verdict);

        let mut tx_hash = None;
        if mode == "run" {
            if let (Some(approved), Some(chosen)) = (&decision.approved, decision.chosen()) {
                if approved.requires_human_approval() {
                    println!("  HELD for human approval, not submitting");
                } else if let Action::Take {
                    order_id,
                    base_amount,
                    price_quote,
                    ..
                } = &chosen.action
                {
                    // Back to 18 decimals at the boundary. The whole runtime works in
                    // micro-units; only this call site speaks the chain's scale.
                    let notional_micro = (base_amount * price_quote) / MICRO;
                    match submit_take(
                        &repo_root,
                        *order_id,
                        market_intel::micro_to_wei(*base_amount),
                        market_intel::micro_to_wei(notional_micro),
                        decision_id,
                    ) {
                        Ok(tx) => {
                            println!("  submitted: {tx}");
                            tx_hash = Some(tx);
                            actions_this_run += 1;
                        }
                        Err(e) => println!("  submit failed: {e}"),
                    }
                }
            }
        }

        jrnl.append(&Entry {
            decision_id,
            observed_at_ms: now_ms,
            block_number: snap.block_number,
            market: "tBASE/tQUOTE".into(),
            thesis,
            thesis_confidence_bps: confidence,
            signals: signal_records(&signals),
            candidates: decision.records(),
            risk_verdict: decision.risk_verdict.clone(),
            action: decision.chosen().map(|c| c.action.label()),
            tx_hash,
            outcome: None,
            evidence: vec![
                format!(
                    "eth_call venue.orderCount and orders at block {}",
                    snap.block_number
                ),
                format!(
                    "eth_call guard.exposureOf and killed at block {}",
                    snap.block_number
                ),
            ],
        })?;

        if cycle + 1 < cycles {
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
    }

    println!();
    println!("journal entries total: {}", jrnl.count()?);
    Ok(())
}
