//! Task 2.1.7: exhaustive property tests, not example-based ones.
//!
//! The properties here are the same statements the Certora specs will assert in
//! Phase 3. Proptest samples the space; the prover will close it./// One kill-switch case: a label, a mutation that trips the condition, and the
/// reason the engine must report. Named because clippy is right that the inline
/// tuple array was hard to read.
type KillCase = (&'static str, fn(&mut RiskContext), KillReason);

use super::*;
use core_types::{MarketId, Position, Side, Stamped};
use proptest::prelude::*;

fn engine() -> RiskEngine {
    RiskEngine::new(Limits::conservative_testnet())
}

fn mk_intent(kind: InstrumentKind, side: Side, size: Micro, price: Micro) -> OrderIntent {
    OrderIntent {
        market: MarketId::new("M1"),
        kind,
        side,
        size_micro: size,
        limit_price_micro: price,
        decision_id: 7,
    }
}

fn empty_book(free_margin: Micro) -> Portfolio {
    Portfolio {
        positions: vec![],
        free_margin_micro: free_margin,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    }
}

// ---------------------------------------------------------------------------
// Example-based tests for the specific behaviours worth naming.
// ---------------------------------------------------------------------------

#[test]
fn a_small_order_on_an_empty_book_is_approved() {
    let e = engine();
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, MICRO, 10 * MICRO);
    let v = e.evaluate(
        &i,
        &empty_book(100 * MICRO),
        &RiskContext::healthy_at(1_000),
    );
    assert!(v.is_ok(), "expected approval, got {v:?}");
}

#[test]
fn an_oversized_order_is_refused_with_the_numbers() {
    let e = engine();
    // 26 quote notional against a 25 limit.
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, 26 * MICRO, MICRO);
    match e.evaluate(
        &i,
        &empty_book(1_000 * MICRO),
        &RiskContext::healthy_at(1_000),
    ) {
        Err(Refusal::OrderNotionalTooLarge { got, limit }) => {
            assert_eq!(got, 26 * MICRO);
            assert_eq!(limit, 25 * MICRO);
        }
        other => panic!("expected OrderNotionalTooLarge, got {other:?}"),
    }
}

#[test]
fn the_kill_switch_refuses_everything_including_a_trivially_safe_order() {
    let e = engine();
    let tiny = mk_intent(InstrumentKind::Spot, Side::Buy, 1, 1);
    let mut ctx = RiskContext::healthy_at(1_000);
    ctx.manual_kill = true;
    assert!(matches!(
        e.evaluate(&tiny, &empty_book(1_000 * MICRO), &ctx),
        Err(Refusal::Killed(KillReason::Manual))
    ));
}

#[test]
fn daily_loss_breach_engages_the_kill_switch() {
    let e = engine();
    let pf = Portfolio {
        realized_pnl_today_micro: -20 * MICRO, // exactly at the limit
        ..empty_book(1_000 * MICRO)
    };
    assert_eq!(
        e.kill_check(&pf, &RiskContext::healthy_at(0)),
        Some(KillReason::DailyLossBreached)
    );
}

#[test]
fn a_stale_mark_price_refuses_new_orders() {
    let e = engine();
    let pf = Portfolio {
        positions: vec![Position {
            market: MarketId::new("OLD"),
            kind: InstrumentKind::Spot,
            net_size_micro: MICRO,
            mark_price_micro: Stamped::new(MICRO, 0),
        }],
        ..empty_book(1_000 * MICRO)
    };
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, MICRO, MICRO);
    // 10_001 ms later, against a 10_000 ms allowance.
    match e.evaluate(&i, &pf, &RiskContext::healthy_at(10_001)) {
        Err(Refusal::MarkPriceStale { age_ms, max_age_ms }) => {
            assert_eq!(age_ms, 10_001);
            assert_eq!(max_age_ms, 10_000);
        }
        other => panic!("expected MarkPriceStale, got {other:?}"),
    }
}

#[test]
fn retrying_a_refused_order_does_not_eventually_succeed() {
    // Guards against any hidden accumulator or backoff that could soften a
    // refusal. The engine is pure, so this must hold, and the test exists to
    // catch a future change that makes it impure.
    let e = engine();
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, 26 * MICRO, MICRO);
    let pf = empty_book(1_000 * MICRO);
    for attempt in 0..1_000 {
        let v = e.evaluate(&i, &pf, &RiskContext::healthy_at(1_000 + attempt));
        assert!(v.is_err(), "refusal softened on attempt {attempt}");
    }
}

#[test]
fn human_approval_is_flagged_above_the_threshold_and_not_below() {
    let e = engine();
    let pf = empty_book(1_000 * MICRO);
    let big = mk_intent(InstrumentKind::Spot, Side::Buy, 20 * MICRO, MICRO);
    let small = mk_intent(InstrumentKind::Spot, Side::Buy, 10 * MICRO, MICRO);
    assert!(e
        .evaluate(&big, &pf, &RiskContext::healthy_at(0))
        .unwrap()
        .requires_human_approval());
    assert!(!e
        .evaluate(&small, &pf, &RiskContext::healthy_at(0))
        .unwrap()
        .requires_human_approval());
}

#[test]
fn an_order_exactly_at_the_notional_limit_is_approved() {
    // Boundary case. Found by the mutation gate: changing `>` to `>=` on the
    // order notional check originally stayed GREEN, which meant no test pinned
    // the boundary. The limit is inclusive, so exactly-at-limit must pass.
    let e = engine();
    let limit = e.limits().max_order_notional_micro;
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, limit, MICRO);
    assert_eq!(i.notional_micro(), limit);
    let v = e.evaluate(&i, &empty_book(1_000 * MICRO), &RiskContext::healthy_at(0));
    assert!(v.is_ok(), "exactly-at-limit must be approved, got {v:?}");

    // And one micro-unit above must be refused, pinning the boundary from both
    // sides so neither `>` nor `>=` can pass the suite.
    let over = mk_intent(InstrumentKind::Spot, Side::Buy, limit + 1, MICRO);
    assert!(matches!(
        e.evaluate(
            &over,
            &empty_book(1_000 * MICRO),
            &RiskContext::healthy_at(0)
        ),
        Err(Refusal::OrderNotionalTooLarge { .. })
    ));
}

#[test]
fn every_kill_context_flag_independently_halts_the_agent() {
    // Found by the mutation gate: neutralising the data_stale branch stayed
    // GREEN, because the killed_means_nothing_is_approved property only asserts
    // when kill_check already returns Some. Neutralising the branch made the
    // property vacuous. Each flag now has a direct, non-vacuous test.
    let e = engine();
    let pf = empty_book(1_000 * MICRO);
    let tiny = mk_intent(InstrumentKind::Spot, Side::Buy, MICRO, MICRO);

    let cases: [KillCase; 4] = [
        ("manual", |c| c.manual_kill = true, KillReason::Manual),
        (
            "data_stale",
            |c| c.data_stale = true,
            KillReason::MarketDataStale,
        ),
        (
            "rpc_failed",
            |c| c.rpc_failed = true,
            KillReason::RpcFailure,
        ),
        (
            "reconciliation",
            |c| c.reconciliation_mismatch = true,
            KillReason::PositionReconciliationMismatch,
        ),
    ];

    for (label, set_flag, expected) in cases {
        let mut ctx = RiskContext::healthy_at(0);
        set_flag(&mut ctx);
        assert_eq!(
            e.kill_check(&pf, &ctx),
            Some(expected),
            "{label} did not trip kill_check"
        );
        assert_eq!(
            e.evaluate(&tiny, &pf, &ctx),
            Err(Refusal::Killed(expected)),
            "{label} did not refuse a trivially safe order"
        );
    }
}

#[test]
fn zero_and_negative_sizes_are_refused() {
    let e = engine();
    let pf = empty_book(1_000 * MICRO);
    for size in [0, -1, -MICRO] {
        let i = mk_intent(InstrumentKind::Spot, Side::Buy, size, MICRO);
        assert!(matches!(
            e.evaluate(&i, &pf, &RiskContext::healthy_at(0)),
            Err(Refusal::NonPositiveSize)
        ));
    }
}

// ---------------------------------------------------------------------------
// Phase 5: RWA-specific refusals.
// ---------------------------------------------------------------------------

fn healthy_rwa() -> RwaState {
    RwaState {
        oracle_age_secs: 60,
        issuer_paused: false,
        seconds_until_window: 200_000,
        divergence_bps: 50,
        yield_index_micro: MICRO,
    }
}

fn rwa_intent(size: Micro) -> OrderIntent {
    OrderIntent {
        market: MarketId::new("RWA/tQUOTE"),
        kind: InstrumentKind::RwaLinked,
        side: Side::Buy,
        size_micro: size,
        limit_price_micro: MICRO,
        decision_id: 1,
    }
}

#[test]
fn a_healthy_rwa_instrument_trades_normally() {
    let e = engine();
    let ctx = RiskContext::healthy_at(0).with_rwa(healthy_rwa());
    assert!(e
        .evaluate(&rwa_intent(MICRO), &empty_book(1_000 * MICRO), &ctx)
        .is_ok());
}

#[test]
fn an_rwa_market_with_unreadable_state_fails_closed() {
    // The distinction that matters: no RWA state is not the same as healthy RWA
    // state. Defaulting the fields would let a failed read look like a good
    // instrument, which is the worst possible direction for this error.
    let e = engine();
    let ctx = RiskContext::healthy_at(0); // no .with_rwa
    assert_eq!(
        e.evaluate(&rwa_intent(MICRO), &empty_book(1_000 * MICRO), &ctx),
        Err(Refusal::RwaStateUnavailable)
    );
}

#[test]
fn each_rwa_condition_refuses_independently_with_its_numbers() {
    let e = engine();
    let pf = empty_book(1_000 * MICRO);
    let p = *e.rwa_policy();

    let paused = RwaState {
        issuer_paused: true,
        ..healthy_rwa()
    };
    assert_eq!(
        e.evaluate(
            &rwa_intent(MICRO),
            &pf,
            &RiskContext::healthy_at(0).with_rwa(paused)
        ),
        Err(Refusal::RwaIssuerPaused)
    );

    let stale = RwaState {
        oracle_age_secs: p.max_oracle_age_secs + 1,
        ..healthy_rwa()
    };
    assert_eq!(
        e.evaluate(
            &rwa_intent(MICRO),
            &pf,
            &RiskContext::healthy_at(0).with_rwa(stale)
        ),
        Err(Refusal::RwaOracleStale {
            age_secs: p.max_oracle_age_secs + 1,
            max_secs: p.max_oracle_age_secs
        })
    );

    let near_window = RwaState {
        seconds_until_window: p.window_buffer_secs - 1,
        ..healthy_rwa()
    };
    assert_eq!(
        e.evaluate(
            &rwa_intent(MICRO),
            &pf,
            &RiskContext::healthy_at(0).with_rwa(near_window)
        ),
        Err(Refusal::RwaRedemptionWindowTooClose {
            until_secs: p.window_buffer_secs - 1,
            buffer_secs: p.window_buffer_secs
        })
    );

    let divergent = RwaState {
        divergence_bps: p.max_divergence_bps + 1,
        ..healthy_rwa()
    };
    assert_eq!(
        e.evaluate(
            &rwa_intent(MICRO),
            &pf,
            &RiskContext::healthy_at(0).with_rwa(divergent)
        ),
        Err(Refusal::RwaOracleMarketDivergence {
            got_bps: p.max_divergence_bps + 1,
            limit_bps: p.max_divergence_bps
        })
    );
}

#[test]
fn an_open_redemption_window_does_not_trip_the_buffer() {
    // seconds_until_window == 0 means a window is OPEN right now, which is the safest
    // time to trade, not the most dangerous. An off-by-one here would refuse exactly
    // when it should permit.
    let e = engine();
    let open = RwaState {
        seconds_until_window: 0,
        ..healthy_rwa()
    };
    assert!(e
        .evaluate(
            &rwa_intent(MICRO),
            &empty_book(1_000 * MICRO),
            &RiskContext::healthy_at(0).with_rwa(open)
        )
        .is_ok());
}

#[test]
fn exiting_an_rwa_position_is_never_blocked_by_any_rwa_condition() {
    // THE asymmetry, offchain half. Mirrors the onchain proof
    // check_reduceIsNeverBlockedByRwaConditions.
    let e = engine();
    let pf = Portfolio {
        positions: vec![Position {
            market: MarketId::new("RWA/tQUOTE"),
            kind: InstrumentKind::RwaLinked,
            net_size_micro: 10 * MICRO,
            mark_price_micro: Stamped::new(MICRO, 0),
        }],
        ..empty_book(1_000 * MICRO)
    };
    let awful = RwaState {
        oracle_age_secs: 999_999,
        issuer_paused: true,
        seconds_until_window: 1,
        divergence_bps: 9_999,
        yield_index_micro: MICRO,
    };
    let ctx = RiskContext::healthy_at(0).with_rwa(awful);

    // Adding is refused.
    let mut add = rwa_intent(MICRO);
    add.side = Side::Buy;
    assert!(e.evaluate(&add, &pf, &ctx).unwrap_err().is_rwa_specific());

    // Selling reduces the long, so it must pass every RWA check.
    let mut exit = rwa_intent(5 * MICRO);
    exit.side = Side::Sell;
    let v = e.evaluate(&exit, &pf, &ctx);
    assert!(v.is_ok(), "exit was blocked: {v:?}");
}

#[test]
fn the_reduce_exemption_cannot_be_abused_to_add_exposure() {
    // A sell that is larger than the existing long still counts as reducing under the
    // sign test, which is intentional: it flattens and then reverses, and the generic
    // caps bound the reversal. What must NOT happen is a same-direction order slipping
    // through as a "reduce".
    let e = engine();
    let pf = Portfolio {
        positions: vec![Position {
            market: MarketId::new("RWA/tQUOTE"),
            kind: InstrumentKind::RwaLinked,
            net_size_micro: 10 * MICRO,
            mark_price_micro: Stamped::new(MICRO, 0),
        }],
        ..empty_book(1_000 * MICRO)
    };
    let paused = RwaState {
        issuer_paused: true,
        ..healthy_rwa()
    };
    let ctx = RiskContext::healthy_at(0).with_rwa(paused);

    // Same direction as the position: adding, so refused.
    let mut add_more = rwa_intent(MICRO);
    add_more.side = Side::Buy;
    assert_eq!(
        e.evaluate(&add_more, &pf, &ctx),
        Err(Refusal::RwaIssuerPaused)
    );
}

#[test]
fn rwa_refusals_do_not_leak_onto_a_pure_crypto_market() {
    // The side-by-side property. Identical order shape, identical dreadful RWA state,
    // and the Spot market is unaffected because the RWA checks are gated on
    // instrument kind. Without this, "RWA intelligence" would just be a global brake.
    let e = engine();
    let pf = empty_book(1_000 * MICRO);
    let awful = RwaState {
        oracle_age_secs: 999_999,
        issuer_paused: true,
        seconds_until_window: 1,
        divergence_bps: 9_999,
        yield_index_micro: MICRO,
    };
    let ctx = RiskContext::healthy_at(0).with_rwa(awful);

    let mut spot = rwa_intent(MICRO);
    spot.kind = InstrumentKind::Spot;
    spot.market = MarketId::new("tBASE/tQUOTE");
    assert!(
        e.evaluate(&spot, &pf, &ctx).is_ok(),
        "crypto market must be unaffected by RWA conditions"
    );

    let rwa = rwa_intent(MICRO);
    let refusal = e.evaluate(&rwa, &pf, &ctx).unwrap_err();
    assert!(
        refusal.is_rwa_specific(),
        "expected an RWA refusal, got {refusal:?}"
    );
}

#[test]
fn rwa_refusals_are_labelled_as_rwa_specific_and_generic_ones_are_not() {
    assert!(Refusal::RwaIssuerPaused.is_rwa_specific());
    assert!(Refusal::RwaStateUnavailable.is_rwa_specific());
    assert!(!Refusal::NonPositiveSize.is_rwa_specific());
    assert!(!Refusal::Killed(KillReason::Manual).is_rwa_specific());
}

// ---------------------------------------------------------------------------
// Properties. These are the Phase 3 spec statements.
// ---------------------------------------------------------------------------

// Bounded to keep notionals inside i128 comfortably while still covering the
// interesting region around every limit.
prop_compose! {
    fn arb_intent()(
        kind in prop_oneof![
            Just(InstrumentKind::Spot),
            Just(InstrumentKind::Perp),
            Just(InstrumentKind::Outcome),
            Just(InstrumentKind::RwaLinked),
        ],
        buy in any::<bool>(),
        size in -5i128..200i128,
        price in -5i128..200i128,
        market in prop_oneof![Just("M1"), Just("M2")],
    ) -> OrderIntent {
        OrderIntent {
            market: MarketId::new(market),
            kind,
            side: if buy { Side::Buy } else { Side::Sell },
            size_micro: size * MICRO / 10,
            limit_price_micro: price * MICRO / 10,
            decision_id: 1,
        }
    }
}

prop_compose! {
    fn arb_portfolio()(
        n in 0usize..4,
        sizes in prop::collection::vec(-50i128..50i128, 0..4),
        marks in prop::collection::vec(1i128..50i128, 0..4),
        free in -10i128..500i128,
        pnl in -50i128..50i128,
        losses in 0u32..8,
        mark_age in 0u64..30_000,
    ) -> (Portfolio, u64) {
        let mut positions = Vec::new();
        for idx in 0..n.min(sizes.len()).min(marks.len()) {
            positions.push(Position {
                market: MarketId::new(if idx % 2 == 0 { "M1" } else { "M2" }),
                kind: if idx % 3 == 0 { InstrumentKind::RwaLinked } else { InstrumentKind::Spot },
                net_size_micro: sizes[idx] * MICRO / 10,
                mark_price_micro: Stamped::new(marks[idx] * MICRO, 0),
            });
        }
        (
            Portfolio {
                positions,
                free_margin_micro: free * MICRO,
                realized_pnl_today_micro: pnl * MICRO,
                consecutive_losses: losses,
            },
            mark_age,
        )
    }
}

proptest! {
    /// THE central property. If the engine approved it, no limit is exceeded.
    /// This is the statement that makes the whole architecture worth anything.
    #[test]
    fn approval_implies_every_limit_holds(
        intent in arb_intent(),
        (pf, mark_age) in arb_portfolio(),
        actions in 0u32..60,
    ) {
        let e = engine();
        let l = e.limits();
        let now = mark_age; // marks stamped at 0, so now == their age
        let mut ctx = RiskContext::healthy_at(now);
        ctx.actions_last_minute = actions;

        if let Ok(approved) = e.evaluate(&intent, &pf, &ctx) {
            let i = approved.get();
            let notional = i.notional_micro();

            prop_assert!(i.size_micro > 0);
            prop_assert!(i.limit_price_micro > 0);
            prop_assert!(notional <= l.max_order_notional_micro);
            prop_assert!(actions < l.max_actions_per_minute);

            let projected_market =
                (pf.exposure_in_market_micro(&i.market) + i.signed_notional_micro()).abs();
            prop_assert!(projected_market <= l.max_market_notional_micro);

            let projected_gross = pf.gross_exposure_micro() + notional;
            prop_assert!(projected_gross <= l.max_gross_notional_micro);

            let projected_net = (pf.net_exposure_micro() + i.signed_notional_micro()).abs();
            prop_assert!(projected_net <= l.max_net_skew_micro);

            prop_assert!(pf.free_margin_micro - notional >= l.min_free_margin_micro);

            if let Some(age) = pf.worst_mark_age_ms(now) {
                prop_assert!(age <= l.max_mark_age_ms);
            }

            // Kill conditions cannot hold on an approved path.
            prop_assert!(pf.realized_pnl_today_micro > -l.daily_loss_limit_micro);
            prop_assert!(pf.consecutive_losses < l.max_consecutive_losses);
        }
    }

    /// Once any kill condition holds, nothing is ever approved, regardless of how
    /// harmless the order looks.
    #[test]
    fn killed_means_nothing_is_approved(
        intent in arb_intent(),
        (pf, mark_age) in arb_portfolio(),
        which in 0u8..6,
    ) {
        let e = engine();
        let mut ctx = RiskContext::healthy_at(mark_age);
        match which {
            0 => ctx.manual_kill = true,
            1 => ctx.data_stale = true,
            2 => ctx.rpc_failed = true,
            3 => ctx.reconciliation_mismatch = true,
            4 => { /* rely on pnl from the generated portfolio */ }
            _ => { /* rely on consecutive losses */ }
        }
        if e.kill_check(&pf, &ctx).is_some() {
            let v = e.evaluate(&intent, &pf, &ctx);
            let killed = matches!(v, Err(Refusal::Killed(_)));
            prop_assert!(killed, "expected Killed, got {:?}", v);
        }
    }

    /// Determinism. Same inputs, same answer, always. A retry loop cannot wear
    /// the engine down.
    #[test]
    fn evaluation_is_deterministic(
        intent in arb_intent(),
        (pf, mark_age) in arb_portfolio(),
    ) {
        let e = engine();
        let ctx = RiskContext::healthy_at(mark_age);
        let a = e.evaluate(&intent, &pf, &ctx);
        let b = e.evaluate(&intent, &pf, &ctx);
        prop_assert_eq!(a.is_ok(), b.is_ok());
        if let (Ok(x), Ok(y)) = (a, b) {
            prop_assert_eq!(x.get(), y.get());
        }
    }

    /// Monotonicity in size: if an order is refused for being too large, every
    /// larger order at the same price is also refused. Guards against a hole in
    /// the middle of the size range.
    #[test]
    fn refusal_for_size_is_monotone(
        (pf, mark_age) in arb_portfolio(),
        price in 1i128..40i128,
        size in 1i128..60i128,
        extra in 1i128..40i128,
    ) {
        let e = engine();
        let ctx = RiskContext::healthy_at(mark_age);
        let small = mk_intent(InstrumentKind::Spot, Side::Buy, size * MICRO, price * MICRO);
        let large = mk_intent(
            InstrumentKind::Spot, Side::Buy, (size + extra) * MICRO, price * MICRO,
        );
        // Bound to locals first: prop_assert! passes its expression through
        // concat!, which misreads a `{ .. }` pattern as a format string.
        let small_refused_for_size = matches!(
            e.evaluate(&small, &pf, &ctx),
            Err(Refusal::OrderNotionalTooLarge { .. })
        );
        let large_refused_for_size = matches!(
            e.evaluate(&large, &pf, &ctx),
            Err(Refusal::OrderNotionalTooLarge { .. })
        );
        if small_refused_for_size {
            prop_assert!(large_refused_for_size);
        }
    }
}

// ===========================================================================
// Task 1.7: tests that kill mutants cargo-mutants found SURVIVING.
//
// 57 caught, 37 missed on the first run. Each test below names the mutant it kills, so these
// are distinguishable from coverage padding and so the set can be checked by re-running
// `bash scripts/59-cargo-mutants.sh`.
//
// The common cause of group C, D and E below is worth stating once: almost every existing test
// runs against an EMPTY book. On an empty book `existing + order` and `existing - order` agree,
// so the post-trade projection logic (the thing the comment at lib.rs:448 says exists to stop a
// book creeping past a limit one order at a time) was never actually exercised.
// ===========================================================================

/// A book with real exposure, which is what group C and D need. Two positions in different
/// markets, both long, so gross and net are non-zero and differ from any single market.
fn book_with_exposure() -> Portfolio {
    Portfolio {
        positions: vec![
            Position {
                market: MarketId::new("M1"),
                kind: InstrumentKind::Spot,
                net_size_micro: 10 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
            Position {
                market: MarketId::new("M2"),
                kind: InstrumentKind::Spot,
                net_size_micro: 20 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
        ],
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    }
}

// ---------------------------------------------------------------------------
// GROUP A: the shipped defaults. Kills lib.rs:69, 70, 76 (* -> +, * -> /).
// ---------------------------------------------------------------------------

/// Kills: `replace * with +` and `replace * with /` in `Limits::conservative_testnet`.
///
/// Why this test did not exist and should have: every other test constructs its own limits, so
/// the defaults the DEMO ACTUALLY RUNS WITH were asserted nowhere.
#[test]
fn the_shipped_testnet_defaults_are_exactly_what_they_claim_to_be() {
    let l = Limits::conservative_testnet();
    assert_eq!(l.max_market_notional_micro, 50 * MICRO);
    assert_eq!(l.max_gross_notional_micro, 200 * MICRO);
    assert_eq!(l.max_net_skew_micro, 75 * MICRO);
    assert_eq!(l.max_order_notional_micro, 25 * MICRO);
    assert_eq!(l.min_free_margin_micro, 5 * MICRO);
    assert_eq!(l.daily_loss_limit_micro, 20 * MICRO);
    assert_eq!(l.max_consecutive_losses, 4);
    assert_eq!(l.max_mark_age_ms, 10_000);
    assert_eq!(l.max_actions_per_minute, 30);
    assert_eq!(l.human_approval_threshold_micro, 15 * MICRO);
    assert_eq!(l.max_rwa_share_bps, 4_000);
    assert_eq!(l.max_rwa_absolute_micro, 10 * MICRO);
}

/// Kills the same mutants a second way, and this one keeps guarding after a legitimate retune
/// of the numbers, which the exact-value test above does not.
#[test]
fn the_testnet_defaults_are_internally_coherent() {
    let l = Limits::conservative_testnet();

    // A single order cannot exceed one market's cap; no market's cap can exceed gross.
    // If either inverted, one of the limits would be unreachable and therefore dead code.
    assert!(l.max_order_notional_micro <= l.max_market_notional_micro);
    assert!(l.max_market_notional_micro <= l.max_gross_notional_micro);

    // Human approval must trigger BELOW the hard order cap or it can never fire: anything big
    // enough to need review would already be refused.
    assert!(l.human_approval_threshold_micro < l.max_order_notional_micro);

    // The RWA absolute cap must be reachable inside gross, otherwise the share cap is the only
    // binding constraint. Same class of bug as v1's unsatisfiable RWA share cap.
    assert!(l.max_rwa_absolute_micro < l.max_gross_notional_micro);

    // Every micro-denominated limit is a whole number of units. `5 + MICRO` is not.
    for v in [
        l.max_market_notional_micro,
        l.max_gross_notional_micro,
        l.max_net_skew_micro,
        l.max_order_notional_micro,
        l.min_free_margin_micro,
        l.daily_loss_limit_micro,
        l.human_approval_threshold_micro,
        l.max_rwa_absolute_micro,
    ] {
        assert_eq!(v % MICRO, 0, "limit {v} is not a whole number of units");
    }
    assert!(
        l.max_rwa_share_bps <= 10_000,
        "a share cap above 100% is unsatisfiable"
    );
}

// ---------------------------------------------------------------------------
// GROUP B: boundaries. Every limit is a MAXIMUM, so equality is inside policy.
// Each of these asserts BOTH directions, because a test that only checks limit+1 passes
// under `>` -> `>=` unchanged, which is how all 18 survived.
// ---------------------------------------------------------------------------

/// Kills: lib.rs:441 region and lib.rs:518 (`>` -> `>=` on the human-approval threshold).
/// The order cap and the approval threshold are checked together because a single order sits on
/// both boundaries and the interaction is the interesting part.
#[test]
fn the_order_notional_boundary_and_the_approval_threshold_are_both_inclusive() {
    let e = engine();
    let l = Limits::conservative_testnet();
    let pf = empty_book(1_000 * MICRO);
    let ctx = RiskContext::healthy_at(0);

    // Exactly at the order cap: allowed. 25 units of notional against a 25 cap.
    let at_cap = mk_intent(InstrumentKind::Spot, Side::Buy, 25 * MICRO, MICRO);
    let v = e.evaluate(&at_cap, &pf, &ctx);
    assert!(
        v.is_ok(),
        "notional exactly at the cap must be approved, got {v:?}"
    );

    // One micro-unit over: refused.
    let over = mk_intent(InstrumentKind::Spot, Side::Buy, 25 * MICRO + 1, MICRO);
    assert!(matches!(
        e.evaluate(&over, &pf, &ctx),
        Err(Refusal::OrderNotionalTooLarge { .. })
    ));

    // Human approval fires STRICTLY ABOVE the threshold, so exactly at it does not.
    let at_threshold = mk_intent(
        InstrumentKind::Spot,
        Side::Buy,
        l.human_approval_threshold_micro,
        MICRO,
    );
    let approved = e
        .evaluate(&at_threshold, &pf, &ctx)
        .expect("within all limits");
    assert!(
        !approved.requires_human_approval(),
        "notional exactly at the threshold does not require review"
    );

    let past_threshold = mk_intent(
        InstrumentKind::Spot,
        Side::Buy,
        l.human_approval_threshold_micro + 1,
        MICRO,
    );
    let approved = e
        .evaluate(&past_threshold, &pf, &ctx)
        .expect("still under the order cap");
    assert!(
        approved.requires_human_approval(),
        "one micro-unit past the threshold requires review"
    );
}

/// Kills: lib.rs:432 (`>` -> `>=` on mark age).
#[test]
fn the_mark_age_boundary_is_inclusive_of_the_maximum() {
    let e = engine();
    let l = Limits::conservative_testnet();
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, MICRO, MICRO);

    let mut pf = book_with_exposure();
    pf.positions[0].mark_price_micro = Stamped::new(MICRO, 0);
    pf.positions[1].mark_price_micro = Stamped::new(MICRO, 0);

    // now_ms exactly max_mark_age_ms after the observation: the mark is at its age limit and
    // still usable.
    let ctx = RiskContext::healthy_at(l.max_mark_age_ms);
    let v = e.evaluate(&i, &pf, &ctx);
    assert!(
        v.is_ok(),
        "a mark exactly at the age limit is still fresh, got {v:?}"
    );

    let ctx = RiskContext::healthy_at(l.max_mark_age_ms + 1);
    assert!(matches!(
        e.evaluate(&i, &pf, &ctx),
        Err(Refusal::MarkPriceStale { .. })
    ));
}

/// Kills: lib.rs:453 (`+` -> `-`) and lib.rs:454 (`>` -> `>=`, `>` -> `==`).
///
/// This is the group C case in its clearest form. The book already holds 10 units of exposure in
/// M1. A 40-unit order projects to 50, exactly the market cap, and must be allowed; 41 projects
/// to 51 and must be refused. With `existing - order` the projection would be |10 - 41| = 31 and
/// the refusal would never fire, which is the creep-past-the-limit bug the projection prevents.
#[test]
fn the_market_notional_projection_adds_to_existing_exposure_and_its_boundary_is_inclusive() {
    let e = engine();
    let pf = book_with_exposure(); // M1 holds 10 units, M2 holds 20
    let ctx = RiskContext::healthy_at(0);

    // Sanity anchor, so a change to the fixture cannot silently invalidate the arithmetic below.
    assert_eq!(
        pf.exposure_in_market_micro(&MarketId::new("M1")),
        10 * MICRO
    );

    // Order cap is 25, so approach the 50 market cap in two steps rather than one big order.
    // 10 existing + 25 = 35, under the cap.
    let step = mk_intent(InstrumentKind::Spot, Side::Buy, 25 * MICRO, MICRO);
    assert!(e.evaluate(&step, &pf, &ctx).is_ok());

    // Now put the book at exactly the cap boundary: 40 existing + 10 = 50.
    let mut at_cap_book = book_with_exposure();
    at_cap_book.positions[0].net_size_micro = 40 * MICRO;
    let ten = mk_intent(InstrumentKind::Spot, Side::Buy, 10 * MICRO, MICRO);
    let v = e.evaluate(&ten, &at_cap_book, &ctx);
    assert!(
        v.is_ok(),
        "projecting to exactly the market cap must be approved, got {v:?}"
    );

    // 41 existing + 10 = 51: refused. Under `existing - order` this is |41 - 10| = 31 and passes.
    let mut over_book = book_with_exposure();
    over_book.positions[0].net_size_micro = 41 * MICRO;
    assert!(
        matches!(
            e.evaluate(&ten, &over_book, &ctx),
            Err(Refusal::MarketNotionalTooLarge { .. })
        ),
        "projected market exposure of 51 against a 50 cap must be refused"
    );
}

/// Kills: lib.rs:466 (`+` -> `-`) and lib.rs:467 (`>` -> `>=`, `>` -> `==`).
///
/// Gross is bounded by current gross plus this order's notional. The fixture's gross is 30, so a
/// 25-unit order projects to 55 against a 200 cap; to reach the boundary the book has to be
/// loaded to 175. Constructed explicitly rather than by looping orders, because a loop would
/// depend on the very projection under test.
#[test]
fn the_gross_projection_adds_to_current_gross_and_its_boundary_is_inclusive() {
    let e = engine();
    let ctx = RiskContext::healthy_at(0);
    let l = Limits::conservative_testnet();

    // FOUR markets, none above the 50 per-market cap, alternating sign so net skew stays tiny
    // while gross accumulates to 175. Building this out of one large position instead is what
    // made the first version of this test fail against the per-market cap: the earlier check
    // fires first, so the test would have been reporting on the wrong limit.
    let spread = |sizes: [i128; 4]| Portfolio {
        positions: sizes
            .iter()
            .enumerate()
            .map(|(i, s)| Position {
                // Bound to a local first: clippy's needless_borrow fires on `&format!(..)`.
                market: {
                    let name = format!("G{i}");
                    MarketId::new(&name)
                },
                kind: InstrumentKind::Spot,
                net_size_micro: s * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            })
            .collect(),
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    };

    // The order goes into a market with NO existing exposure, so the per-market projection is
    // just the order itself.
    let order = OrderIntent {
        market: MarketId::new("FRESH"),
        kind: InstrumentKind::Spot,
        side: Side::Buy,
        size_micro: 25 * MICRO,
        limit_price_micro: MICRO,
        decision_id: 11,
    };

    let pf = spread([44, -44, 44, -43]);
    assert_eq!(pf.gross_exposure_micro(), 175 * MICRO);
    assert_eq!(l.max_gross_notional_micro, 200 * MICRO);
    let v = e.evaluate(&order, &pf, &ctx);
    assert!(
        v.is_ok(),
        "gross projecting to exactly the cap must be approved, got {v:?}"
    );

    // 176 + 25 = 201: refused. Under `current - order` the projection would be 151 and pass,
    // which is the mutant this kills.
    let over = spread([44, -44, 44, -44]);
    assert_eq!(over.gross_exposure_micro(), 176 * MICRO);
    match e.evaluate(&order, &over, &ctx) {
        Err(Refusal::GrossNotionalTooLarge { got, limit }) => {
            assert_eq!(got, 201 * MICRO);
            assert_eq!(limit, 200 * MICRO);
        }
        other => panic!("expected GrossNotionalTooLarge, got {other:?}"),
    }
}

/// Kills: lib.rs:474 (`+` -> `-`) and lib.rs:475 (`>` -> `>=`, `>` -> `==`).
///
/// Net skew is signed, so this also pins the sign convention: a Sell against a long book REDUCES
/// skew. If the projection subtracted instead of added, a Buy that pushes skew past the cap would
/// look like a reduction and pass.
#[test]
fn the_net_skew_projection_is_signed_and_its_boundary_is_inclusive() {
    let e = engine();
    let ctx = RiskContext::healthy_at(0);

    // Two markets, both long, each inside the per-market cap. The order goes to a THIRD market so
    // the per-market check cannot fire first.
    let book = |a: i128, b: i128| Portfolio {
        positions: vec![
            Position {
                market: MarketId::new("N1"),
                kind: InstrumentKind::Spot,
                net_size_micro: a * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
            Position {
                market: MarketId::new("N2"),
                kind: InstrumentKind::Spot,
                net_size_micro: b * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
        ],
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    };
    let buy = OrderIntent {
        market: MarketId::new("N3"),
        kind: InstrumentKind::Spot,
        side: Side::Buy,
        size_micro: 25 * MICRO,
        limit_price_micro: MICRO,
        decision_id: 12,
    };

    // 50 existing net + 25 = exactly the 75 cap.
    let pf = book(30, 20);
    assert_eq!(pf.net_exposure_micro(), 50 * MICRO);
    let v = e.evaluate(&buy, &pf, &ctx);
    assert!(
        v.is_ok(),
        "net projecting to exactly the skew cap must be approved, got {v:?}"
    );

    // 51 + 25 = 76: refused.
    let over = book(31, 20);
    assert_eq!(over.net_exposure_micro(), 51 * MICRO);
    match e.evaluate(&buy, &over, &ctx) {
        Err(Refusal::NetSkewTooLarge { got, limit }) => {
            assert_eq!(got, 76 * MICRO);
            assert_eq!(limit, 75 * MICRO);
        }
        other => panic!("expected NetSkewTooLarge, got {other:?}"),
    }

    // The sign convention, which is what makes the `+` -> `-` mutant detectable rather than
    // merely wrong: the SAME book accepts a Sell, because selling reduces a long skew.
    let sell = OrderIntent {
        side: Side::Sell,
        ..buy.clone()
    };
    assert!(
        e.evaluate(&sell, &over, &ctx).is_ok(),
        "a Sell against a long book reduces skew and must be allowed"
    );
}

/// Kills: lib.rs:482 (`-` -> `+`) and lib.rs:483 (`<` -> `<=`, `<` -> `==`).
///
/// Free margin is the one check where the arithmetic is a SUBTRACTION, and the minimum is a
/// floor rather than a ceiling: leaving exactly the minimum is acceptable, leaving one less is
/// not. Under `free + order` the remaining margin would grow when spending, so an order that
/// drains the account would pass.
#[test]
fn the_free_margin_floor_is_inclusive_and_spending_reduces_margin() {
    let e = engine();
    let ctx = RiskContext::healthy_at(0);
    let l = Limits::conservative_testnet();
    let order = mk_intent(InstrumentKind::Spot, Side::Buy, 20 * MICRO, MICRO);

    // Leaves exactly the minimum: 25 - 20 = 5, and the minimum is 5.
    let pf = empty_book(25 * MICRO);
    let v = e.evaluate(&order, &pf, &ctx);
    assert!(
        v.is_ok(),
        "leaving exactly the minimum is acceptable, got {v:?}"
    );
    assert_eq!(l.min_free_margin_micro, 5 * MICRO);

    // Leaves one micro-unit less than the minimum: refused.
    let pf = empty_book(25 * MICRO - 1);
    match e.evaluate(&order, &pf, &ctx) {
        Err(Refusal::InsufficientFreeMargin {
            would_leave,
            minimum,
        }) => {
            assert_eq!(would_leave, 5 * MICRO - 1);
            assert_eq!(minimum, 5 * MICRO);
        }
        other => panic!("expected InsufficientFreeMargin, got {other:?}"),
    }

    // And the direction of the arithmetic: an order strictly larger than free margin can never
    // be approved, which `free + order` would allow.
    let big = mk_intent(InstrumentKind::Spot, Side::Buy, 20 * MICRO, MICRO);
    assert!(matches!(
        e.evaluate(&big, &empty_book(MICRO), &ctx),
        Err(Refusal::InsufficientFreeMargin { .. })
    ));
}

// ---------------------------------------------------------------------------
// GROUP D: the RWA share cap arithmetic. Kills lib.rs:498, 500, 502, 504, 505.
// These need a book with real gross exposure, because a share is a fraction of gross and on an
// empty book the absolute floor dominates and the arithmetic is never reached.
// ---------------------------------------------------------------------------

/// Kills: lib.rs:498 (`+` -> `-`, `+` -> `*`), lib.rs:500 (`*` -> `+`, `*` -> `/`, `/` -> `*`,
/// `/` -> `%`) and lib.rs:502 (`>` -> `>=`, `>` -> `==`).
///
/// Constructed so the SHARE cap binds rather than the absolute floor: gross must be large enough
/// that 40% of it exceeds the 10-unit absolute cap, i.e. gross above 25.
#[test]
fn the_rwa_share_cap_is_a_real_fraction_of_projected_gross() {
    let e = engine();
    let ctx = RiskContext::healthy_at(0).with_rwa(healthy_rwa());
    let l = Limits::conservative_testnet();
    assert_eq!(l.max_rwa_share_bps, 4_000);

    let rwa_market = MarketId::new("RWA/tQUOTE");
    let order = OrderIntent {
        market: rwa_market.clone(),
        kind: InstrumentKind::RwaLinked,
        side: Side::Buy,
        size_micro: 25 * MICRO,
        limit_price_micro: MICRO,
        decision_id: 13,
    };

    // CASE 1, inside the cap. Non-RWA gross 100 across two opposing markets at the per-market
    // cap, no existing RWA. Projected gross 125, allowance 40% of 125 = 50, projected RWA 25.
    let clean = Portfolio {
        positions: vec![
            Position {
                market: MarketId::new("R1"),
                kind: InstrumentKind::Spot,
                net_size_micro: 50 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
            Position {
                market: MarketId::new("R2"),
                kind: InstrumentKind::Spot,
                net_size_micro: -50 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
        ],
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    };
    assert_eq!(clean.gross_exposure_micro(), 100 * MICRO);
    let v = e.evaluate(&order, &clean, &ctx);
    assert!(
        v.is_ok(),
        "20% RWA share against a 40% cap must be approved, got {v:?}"
    );

    // CASE 2, the share cap binds. Non-RWA gross 40 and existing RWA 20, so gross 60 and
    // projected gross 85. Allowance is 40% of 85 = 34, and max(34, absolute 10) = 34.
    // Projected RWA is 20 + 25 = 45 > 34, so the SHARE cap refuses. Every earlier check passes:
    // the RWA market projects to 45 (inside 50), net to 45 (inside 75), gross to 85 (inside 200).
    let loaded = Portfolio {
        positions: vec![
            Position {
                market: MarketId::new("R1"),
                kind: InstrumentKind::Spot,
                net_size_micro: 20 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
            Position {
                market: MarketId::new("R2"),
                kind: InstrumentKind::Spot,
                net_size_micro: -20 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
            Position {
                market: rwa_market.clone(),
                kind: InstrumentKind::RwaLinked,
                net_size_micro: 20 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
        ],
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    };
    assert_eq!(loaded.gross_exposure_micro(), 60 * MICRO);
    assert_eq!(
        loaded.exposure_of_kind_micro(InstrumentKind::RwaLinked),
        20 * MICRO
    );

    match e.evaluate(&order, &loaded, &ctx) {
        Err(Refusal::RwaShareTooLarge { got_bps, limit_bps }) => {
            assert_eq!(limit_bps, 4_000);
            // 45 of 85 projected gross is 5294 bps. Pinning the exact value is what kills the
            // mutants on the reporting arithmetic at lib.rs:505: any of `*` -> `+`, `/` -> `*`
            // or `/` -> `%` moves this number.
            assert_eq!(
                got_bps, 5_294,
                "the reported share must be the real fraction"
            );
        }
        other => panic!("expected RwaShareTooLarge, got {other:?}"),
    }
}

/// Kills: lib.rs:504 (`>` -> `<`, `>` -> `==`, `>` -> `>=`) and lib.rs:505 (`*` -> `+`,
/// `*` -> `/`, `/` -> `*`, `/` -> `%`), the share REPORTING arithmetic.
///
/// The reported basis points are a claim shown to an operator, so a mutation that reports the
/// wrong share is a real defect even though the refusal itself is correct. Pinning the exact
/// value is what makes the reporting path testable at all.
#[test]
fn the_reported_rwa_share_is_the_actual_share_in_basis_points() {
    let e = engine();
    let ctx = RiskContext::healthy_at(0).with_rwa(healthy_rwa());

    // Construct an exact, checkable fraction: 20 existing RWA + 5 new = 25 projected RWA.
    // Non-RWA gross 25, so projected gross = 25 + 20 + 5 = 50, and the share is exactly 5000 bps.
    let pf = Portfolio {
        positions: vec![
            Position {
                market: MarketId::new("M1"),
                kind: InstrumentKind::Spot,
                net_size_micro: 25 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
            Position {
                market: MarketId::new("RWA/tQUOTE"),
                kind: InstrumentKind::RwaLinked,
                net_size_micro: 20 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
        ],
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    };

    let rwa = OrderIntent {
        market: MarketId::new("RWA/tQUOTE"),
        kind: InstrumentKind::RwaLinked,
        side: Side::Buy,
        size_micro: 5 * MICRO,
        limit_price_micro: MICRO,
        decision_id: 2,
    };

    match e.evaluate(&rwa, &pf, &ctx) {
        Err(Refusal::RwaShareTooLarge { got_bps, limit_bps }) => {
            // 25 of 50 is exactly half.
            assert_eq!(
                got_bps, 5_000,
                "the reported share must be the real fraction"
            );
            assert_eq!(limit_bps, 4_000);
        }
        other => panic!("expected RwaShareTooLarge with an exact share, got {other:?}"),
    }
}

// ---------------------------------------------------------------------------
// GROUP E: is_halted. Kills lib.rs:527 (-> true and -> false).
// Both mutants survived, which is the signature of a public function on the safety surface with
// NO test at all.
// ---------------------------------------------------------------------------

/// Kills: `replace RiskEngine::is_halted -> bool with true` and `with false`.
///
/// Both directions must be asserted or one mutant always survives: a test that only checks the
/// halted case passes under `-> true`, and one that only checks the healthy case passes under
/// `-> false`.
#[test]
fn is_halted_answers_both_ways_and_agrees_with_evaluate() {
    let e = engine();
    let pf = empty_book(1_000 * MICRO);

    let healthy = RiskContext::healthy_at(1_000);
    assert!(
        !e.is_halted(&pf, &healthy),
        "a healthy context is not halted"
    );

    let mut killed = RiskContext::healthy_at(1_000);
    killed.manual_kill = true;
    assert!(e.is_halted(&pf, &killed), "a manual kill halts the agent");

    // And the two surfaces must agree, since is_halted is documented as the convenience form of
    // the same question. A divergence here would mean an operator dashboard could show "running"
    // while every order is being refused.
    let tiny = mk_intent(InstrumentKind::Spot, Side::Buy, 1, 1);
    assert!(e.evaluate(&tiny, &pf, &healthy).is_ok());
    assert!(matches!(
        e.evaluate(&tiny, &pf, &killed),
        Err(Refusal::Killed(KillReason::Manual))
    ));

    // Every other kill reason too, so `is_halted` cannot be right for one cause and wrong for
    // the rest.
    for (label, mutate) in [
        (
            "data_stale",
            (|c: &mut RiskContext| c.data_stale = true) as fn(&mut RiskContext),
        ),
        ("reconciliation", |c: &mut RiskContext| {
            c.reconciliation_mismatch = true
        }),
        ("rpc_failed", |c: &mut RiskContext| c.rpc_failed = true),
    ] {
        let mut ctx = RiskContext::healthy_at(1_000);
        mutate(&mut ctx);
        assert!(e.is_halted(&pf, &ctx), "{label} must halt the agent");
    }
}

// ---------------------------------------------------------------------------
// GROUP B continued: the two rwa_check boundaries.
// ---------------------------------------------------------------------------

/// Kills: lib.rs:335 (`>` -> `>=`), the oracle-age check. The field is named
/// max_oracle_age_secs, so age == max is inside policy.
#[test]
fn the_oracle_age_boundary_is_inclusive_of_the_maximum() {
    let e = engine();
    let policy = RwaPolicy::conservative();
    let pf = empty_book(1_000 * MICRO);

    let mut at_max = healthy_rwa();
    at_max.oracle_age_secs = policy.max_oracle_age_secs;
    let ctx = RiskContext::healthy_at(0).with_rwa(at_max);
    assert!(
        e.evaluate(&rwa_intent(MICRO), &pf, &ctx).is_ok(),
        "age exactly at the maximum is within policy"
    );

    let mut over = healthy_rwa();
    over.oracle_age_secs = policy.max_oracle_age_secs + 1;
    let ctx = RiskContext::healthy_at(0).with_rwa(over);
    assert!(matches!(
        e.evaluate(&rwa_intent(MICRO), &pf, &ctx),
        Err(Refusal::RwaOracleStale { .. })
    ));
}

/// Kills: lib.rs:347 (`>` -> `>=`), the oracle-market divergence check.
#[test]
fn the_divergence_boundary_is_inclusive_of_the_maximum() {
    let e = engine();
    let policy = RwaPolicy::conservative();
    let pf = empty_book(1_000 * MICRO);

    let mut at_max = healthy_rwa();
    at_max.divergence_bps = policy.max_divergence_bps;
    let ctx = RiskContext::healthy_at(0).with_rwa(at_max);
    assert!(
        e.evaluate(&rwa_intent(MICRO), &pf, &ctx).is_ok(),
        "divergence exactly at the maximum is within policy"
    );

    let mut over = healthy_rwa();
    over.divergence_bps = policy.max_divergence_bps + 1;
    let ctx = RiskContext::healthy_at(0).with_rwa(over);
    assert!(matches!(
        e.evaluate(&rwa_intent(MICRO), &pf, &ctx),
        Err(Refusal::RwaOracleMarketDivergence { .. })
    ));
}

/// Kills: lib.rs:502 `replace > with >=` on the RWA share allowance, the last real survivor of
/// the 37 cargo-mutants found.
///
/// The refusal is `projected_rwa > allowance`, so projected RWA exposure EXACTLY EQUAL to the
/// allowance is inside policy and must be approved. Nothing pinned that boundary, so `>` and
/// `>=` were indistinguishable to the whole suite.
///
/// Hitting equality takes arithmetic rather than guessing. With a 40% share cap, equality needs
/// non-RWA gross = 1.5 * (existing RWA + new order). Using existing RWA 10 and an order of 10:
///   projected RWA   = 20
///   projected gross = 30 + 10 + 10 = 50
///   allowance       = max(40% of 50, absolute cap 10) = max(20, 10) = 20
/// so projected RWA equals the allowance exactly. The two non-RWA legs oppose each other so net
/// skew stays clear, and every earlier check passes: market 20 of 50, net 20 of 75, gross 50 of
/// 200, order notional 10 of 25.
#[test]
fn the_rwa_allowance_boundary_is_inclusive() {
    let e = engine();
    let ctx = RiskContext::healthy_at(0).with_rwa(healthy_rwa());
    let rwa_market = MarketId::new("RWA/tQUOTE");

    let book = |existing_rwa: i128| Portfolio {
        positions: vec![
            Position {
                market: MarketId::new("B1"),
                kind: InstrumentKind::Spot,
                net_size_micro: 15 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
            Position {
                market: MarketId::new("B2"),
                kind: InstrumentKind::Spot,
                net_size_micro: -15 * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
            Position {
                market: rwa_market.clone(),
                kind: InstrumentKind::RwaLinked,
                net_size_micro: existing_rwa * MICRO,
                mark_price_micro: Stamped::new(MICRO, 0),
            },
        ],
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    };
    let order = OrderIntent {
        market: rwa_market.clone(),
        kind: InstrumentKind::RwaLinked,
        side: Side::Buy,
        size_micro: 10 * MICRO,
        limit_price_micro: MICRO,
        decision_id: 21,
    };

    // Exactly at the allowance: approved.
    let pf = book(10);
    assert_eq!(pf.gross_exposure_micro(), 40 * MICRO); // 15 + 15 + 10
    let v = e.evaluate(&order, &pf, &ctx);
    assert!(
        v.is_ok(),
        "projected RWA exposure exactly equal to the allowance is within policy, got {v:?}"
    );

    // One micro-unit of existing RWA more, so projected RWA exceeds the allowance: refused.
    // Adding to existing RWA raises the numerator faster than the 40%-of-gross denominator, so
    // this is strictly over.
    let mut over = book(10);
    over.positions[2].net_size_micro += 1;
    assert!(
        matches!(
            e.evaluate(&order, &over, &ctx),
            Err(Refusal::RwaShareTooLarge { .. })
        ),
        "one micro-unit past the allowance must be refused"
    );
}

// ------------------------------------------------------------------ task 8.3: per-user limits

/// A user's own limit refuses an order the SYSTEM would have allowed, and says so with a refusal
/// naming the user's limit rather than the system's.
#[test]
fn per_user_limits_refuse_an_order_the_system_would_allow() {
    let e = engine();
    let pf = empty_book(100 * MICRO);
    let ctx = RiskContext::healthy_at(1_000);

    // 12 units: comfortably inside the system's 25 unit per-order limit.
    let intent = mk_intent(InstrumentKind::Perp, Side::Buy, 12 * MICRO, MICRO);
    assert!(
        e.evaluate(&intent, &pf, &ctx).is_ok(),
        "the system allows 12"
    );

    let user = UserLimits {
        max_order_notional_micro: 10 * MICRO,
        max_market_notional_micro: 50 * MICRO,
    };
    match e.evaluate_for_user(&intent, &pf, &ctx, &user) {
        Err(Refusal::UserLimitExceeded { got, limit }) => {
            assert_eq!(got, 12 * MICRO);
            // The USER's limit is reported, not the system's 25. A ledger row naming a limit the
            // order did not breach would be worse than no row.
            assert_eq!(limit, 10 * MICRO);
        }
        other => panic!("expected UserLimitExceeded, got {other:?}"),
    }
}

/// The user's market bound is checked against PROJECTED exposure, not current, matching the way
/// every other book-level limit in this engine works.
#[test]
fn per_user_market_limit_is_checked_on_projected_exposure() {
    let e = engine();
    let pf = empty_book(100 * MICRO);
    let ctx = RiskContext::healthy_at(1_000);
    let intent = mk_intent(InstrumentKind::Perp, Side::Buy, 8 * MICRO, MICRO);

    let user = UserLimits {
        max_order_notional_micro: 100 * MICRO,
        max_market_notional_micro: 5 * MICRO,
    };
    match e.evaluate_for_user(&intent, &pf, &ctx, &user) {
        Err(Refusal::UserLimitExceeded { got, limit }) => {
            assert_eq!(got, 8 * MICRO);
            assert_eq!(limit, 5 * MICRO);
        }
        other => panic!("expected UserLimitExceeded on the market bound, got {other:?}"),
    }
}

/// A user limit LOOSER than the system's changes nothing. This is the case a user reaches by typing
/// a large number, and it must be safe by construction rather than by validation.
#[test]
fn a_user_limit_looser_than_the_system_changes_nothing() {
    let e = engine();
    let pf = empty_book(100 * MICRO);
    let ctx = RiskContext::healthy_at(1_000);

    // 30 units: beyond the system's 25 unit per-order limit.
    let intent = mk_intent(InstrumentKind::Perp, Side::Buy, 30 * MICRO, MICRO);
    let user = UserLimits {
        max_order_notional_micro: 1_000_000 * MICRO,
        max_market_notional_micro: 1_000_000 * MICRO,
    };

    match e.evaluate_for_user(&intent, &pf, &ctx, &user) {
        Err(Refusal::OrderNotionalTooLarge { got, limit }) => {
            assert_eq!(got, 30 * MICRO);
            // The SYSTEM's limit still binds. The user asked for more and did not get it.
            assert_eq!(limit, 25 * MICRO);
        }
        other => panic!("the system limit must still bind, got {other:?}"),
    }
}

/// `tightened_by` takes a minimum on every field it touches, checked directly so a later edit that
/// reverses an operand is caught at the source rather than through a behavioural test.
#[test]
fn tightened_by_never_raises_a_bound() {
    let base = Limits::conservative_testnet();
    let huge = UserLimits {
        max_order_notional_micro: Micro::MAX,
        max_market_notional_micro: Micro::MAX,
    };
    let t = base.tightened_by(&huge);
    assert_eq!(t.max_order_notional_micro, base.max_order_notional_micro);
    assert_eq!(t.max_market_notional_micro, base.max_market_notional_micro);

    let tiny = UserLimits {
        max_order_notional_micro: 1,
        max_market_notional_micro: 2,
    };
    let t2 = base.tightened_by(&tiny);
    assert_eq!(t2.max_order_notional_micro, 1);
    assert_eq!(t2.max_market_notional_micro, 2);
}

proptest! {
    /// THE CONTAINMENT PROPERTY, and the reason per-user limits are safe to expose to a user who
    /// may type any number at all: anything `evaluate_for_user` approves is also approved by the
    /// plain `evaluate`. A user limit can only ever subtract from what is permitted.
    ///
    /// Stated as containment rather than as "min is used", because containment is the property that
    /// actually matters and it stays true under any future refactor of how tightening is done.
    #[test]
    fn prop_a_user_limit_can_never_widen_what_the_system_allows(
        user_order in 0i128..(1_000 * MICRO),
        user_market in 0i128..(1_000 * MICRO),
        size in 1i128..(200 * MICRO),
        price in 1i128..(3 * MICRO),
    ) {
        let e = engine();
        let pf = empty_book(100 * MICRO);
        let ctx = RiskContext::healthy_at(1_000);
        let intent = mk_intent(InstrumentKind::Perp, Side::Buy, size, price);
        let user = UserLimits {
            max_order_notional_micro: user_order,
            max_market_notional_micro: user_market,
        };

        if e.evaluate_for_user(&intent, &pf, &ctx, &user).is_ok() {
            prop_assert!(
                e.evaluate(&intent, &pf, &ctx).is_ok(),
                "a user limit approved an order the system refuses: size={size} price={price} \
                 user_order={user_order} user_market={user_market}"
            );
        }
    }

    /// And the other direction, so the property is not satisfied vacuously by an implementation
    /// that refuses everything: with unbounded user limits the two paths agree exactly.
    #[test]
    fn prop_unbounded_user_limits_agree_with_the_plain_engine(
        size in 1i128..(200 * MICRO),
        price in 1i128..(3 * MICRO),
    ) {
        let e = engine();
        let pf = empty_book(100 * MICRO);
        let ctx = RiskContext::healthy_at(1_000);
        let intent = mk_intent(InstrumentKind::Perp, Side::Buy, size, price);

        let a = e.evaluate_for_user(&intent, &pf, &ctx, &UserLimits::unbounded()).is_ok();
        let b = e.evaluate(&intent, &pf, &ctx).is_ok();
        prop_assert_eq!(a, b, "unbounded user limits must not change any verdict");
    }
}

/// Task 9.3: write the shipped defaults where the UI reads them.
///
/// This is a test that produces an artifact, which is unusual enough to justify. The alternative is
/// a TypeScript constant holding `25`, and then the crate and the screen are two definitions of one
/// number that drift silently. Here there is one definition and the file is derived from it.
///
/// It also ASSERTS the values, so this is not merely a dump: if someone changes a limit without
/// meaning to, the assertion fails and names the number, rather than the file quietly changing and
/// the UI quietly following.
#[test]
fn export_conservative_defaults_for_the_ui() {
    use std::io::Write;

    let l = Limits::conservative_testnet();

    // The values the UI will display. Asserted so a change is deliberate rather than incidental.
    assert_eq!(l.max_order_notional_micro, 25 * MICRO);
    assert_eq!(l.max_market_notional_micro, 50 * MICRO);
    assert_eq!(l.max_gross_notional_micro, 200 * MICRO);
    assert_eq!(l.daily_loss_limit_micro, 20 * MICRO);
    assert_eq!(l.max_consecutive_losses, 4);
    assert_eq!(l.max_actions_per_minute, 30);

    // Each limit carries WHAT IT PROTECTS AGAINST, because task 9.3 requires a one-line explanation
    // beside every default and that sentence belongs with the number it explains, not in the
    // component that renders it.
    let json = format!(
        r#"{{
  "generatedBy": "cargo test -p risk-engine export_conservative_defaults_for_the_ui",
  "source": "crates/risk-engine/src/lib.rs Limits::conservative_testnet",
  "microPerUnit": {micro},
  "limits": [
    {{
      "key": "maxOrderNotional",
      "label": "Largest single order",
      "micro": {order},
      "protects": "Caps one bad decision. Nothing the agent does can risk more than this at once."
    }},
    {{
      "key": "maxMarketNotional",
      "label": "Largest position in one market",
      "micro": {market},
      "protects": "Stops the agent concentrating everything in a single market."
    }},
    {{
      "key": "maxGrossNotional",
      "label": "Total exposure across all markets",
      "micro": {gross},
      "protects": "Bounds total risk even if every individual order is small."
    }},
    {{
      "key": "dailyLossLimit",
      "label": "Daily loss limit",
      "micro": {loss},
      "protects": "Halts the agent for the day once losses reach this, rather than letting a bad day compound."
    }},
    {{
      "key": "maxConsecutiveLosses",
      "label": "Consecutive losing trades",
      "count": {streak},
      "protects": "Halts the agent when it is repeatedly wrong, which usually means conditions changed."
    }},
    {{
      "key": "maxActionsPerMinute",
      "label": "Actions per minute",
      "count": {rate},
      "protects": "A runaway guard. A loop that misfires cannot spend the account in seconds."
    }}
  ]
}}
"#,
        micro = MICRO,
        order = l.max_order_notional_micro,
        market = l.max_market_notional_micro,
        gross = l.max_gross_notional_micro,
        loss = l.daily_loss_limit_micro,
        streak = l.max_consecutive_losses,
        rate = l.max_actions_per_minute,
    );

    let repo = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
    let path = format!("{repo}/ui-v2/public/data/limits.json");
    let mut f = std::fs::File::create(&path).expect("cannot write limits.json");
    f.write_all(json.as_bytes())
        .expect("cannot write limits.json");
    println!("wrote {path}");
}
