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
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, 1 * MICRO, 10 * MICRO);
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
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, 26 * MICRO, 1 * MICRO);
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
            net_size_micro: 1 * MICRO,
            mark_price_micro: Stamped::new(1 * MICRO, 0),
        }],
        ..empty_book(1_000 * MICRO)
    };
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, 1 * MICRO, 1 * MICRO);
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
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, 26 * MICRO, 1 * MICRO);
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
    let big = mk_intent(InstrumentKind::Spot, Side::Buy, 20 * MICRO, 1 * MICRO);
    let small = mk_intent(InstrumentKind::Spot, Side::Buy, 10 * MICRO, 1 * MICRO);
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
