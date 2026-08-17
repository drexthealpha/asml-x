//! A crossed book must never pay the agent to trade.
//!
//! The UI surfaced a live book crossed at -1333 bps, where the unclamped crossing cost
//! became a credit and inflated expected edge on every candidate. This pins the fix.

use core_types::{InstrumentKind, MarketId, Portfolio, MICRO};
use decision_engine::{Candidate, DecisionEngine, Params};
use market_intel::{MarketIntel, OrderView, VenueSnapshot};
use risk_engine::{Limits, RiskContext, RiskEngine};

fn order(id: u64, buys_base: bool, size_units: i128, price_micro: i128) -> OrderView {
    OrderView {
        id,
        maker_buys_base: buys_base,
        size_base: size_units * MICRO,
        price_quote: price_micro,
        filled_base: 0,
        cancelled: false,
    }
}

fn signals(book: &[OrderView]) -> market_intel::Signals {
    let mut mi = MarketIntel::new(16);
    let mut s = market_intel::Signals::default();
    for t in 0..4u64 {
        s = mi.observe(
            &VenueSnapshot {
                orders: book.to_vec(),
                block_number: 10 + t,
                chain_time_ms: t * 1_000,
            },
            t * 1_000,
        );
    }
    s
}

#[test]
fn a_crossed_book_never_produces_a_negative_crossing_cost() {
    let engine = DecisionEngine::new(
        MarketId::new("tBASE/tQUOTE"),
        InstrumentKind::Spot,
        Params::default(),
    );

    // Crossed: bid 2.4 above ask 2.1, the exact shape seen live.
    let crossed = vec![order(0, true, 2, 2_400_000), order(1, false, 2, 2_100_000)];
    let s = signals(&crossed);
    assert!(s.spread_bps.unwrap().value < 0, "expected a crossed book");

    let cands = engine.generate(&s, &crossed);
    let takes: Vec<&Candidate> = cands
        .iter()
        .filter(|c| c.action != decision_engine::Action::Hold)
        .collect();
    assert!(!takes.is_empty());

    // BOTH ASSERTIONS HERE USED TO BE TAUTOLOGIES, and they guarded a bug that actually shipped.
    //
    //   let directional_only = c.expected_edge_micro + 0;
    //   assert!(c.expected_edge_micro <= directional_only);          // x <= x + 0, always true
    //   assert!(c.expected_edge_micro.is_positive() || c.expected_edge_micro <= 0);  // x>0 || x<=0
    //
    // The second was labelled "sanity" and is true for every integer that exists. Clippy's
    // `identity_op` found the first one; nothing would have found the second. A test named for a
    // bug that cannot fail is worse than no test, because it occupies the slot where a real one
    // would go.
    //
    // THE REAL PROPERTY, and why this form catches the mutation. `crossing_cost` is
    // `(notional * spread_bps.max(0)) / 20_000`. On a crossed book `spread_bps` is negative, so the
    // `.max(0)` floors the cost to exactly zero. Deepening the cross therefore cannot change any
    // edge. Remove the `.max(0)` and the cost goes NEGATIVE, `directional_edge - negative` grows,
    // and a MORE crossed book pays MORE. So: make the book more crossed and require the edges to be
    // identical. No engine internals are needed, and the mutation flips it red.
    let deeper = vec![order(0, true, 2, 3_000_000), order(1, false, 2, 2_100_000)];
    let s_deep = signals(&deeper);
    assert!(
        s_deep.spread_bps.unwrap().value < s.spread_bps.unwrap().value,
        "the second book must be more crossed than the first"
    );
    let deep_cands = engine.generate(&s_deep, &deeper);

    for c in &takes {
        let same: Vec<&Candidate> = deep_cands.iter().filter(|d| d.action == c.action).collect();
        // Only compare candidates that exist on both books; a deeper cross changes which
        // sizes are generated, and a missing counterpart is not a failure.
        for d in same {
            assert_eq!(
                d.expected_edge_micro,
                c.expected_edge_micro,
                "deepening the cross changed expected edge for {}, so the crossing cost is not \
                 floored at zero and a crossed book is paying the agent to trade",
                c.action.label()
            );
        }
    }
}

#[test]
fn an_uncrossed_book_charges_a_real_crossing_cost() {
    let engine = DecisionEngine::new(
        MarketId::new("tBASE/tQUOTE"),
        InstrumentKind::Spot,
        Params::default(),
    );
    // Wide, uncrossed: bid 2.0, ask 2.6. Crossing should cost real money.
    let wide = vec![order(0, true, 2, 2_000_000), order(1, false, 2, 2_600_000)];
    // Tight, uncrossed: bid 2.29, ask 2.31.
    let tight = vec![order(0, true, 2, 2_290_000), order(1, false, 2, 2_310_000)];

    let best_wide = engine
        .generate(&signals(&wide), &wide)
        .into_iter()
        .filter(|c| c.action != decision_engine::Action::Hold)
        .map(|c| c.score_micro())
        .max()
        .unwrap_or(i128::MIN);
    let best_tight = engine
        .generate(&signals(&tight), &tight)
        .into_iter()
        .filter(|c| c.action != decision_engine::Action::Hold)
        .map(|c| c.score_micro())
        .max()
        .unwrap_or(i128::MIN);

    assert!(
        best_tight > best_wide,
        "a tighter spread must score better than a wide one: tight {best_tight} vs wide {best_wide}"
    );
}

#[test]
fn the_risk_gate_still_governs_a_crossed_book() {
    // A market structure anomaly must not become a path around the risk engine.
    let engine = DecisionEngine::new(
        MarketId::new("tBASE/tQUOTE"),
        InstrumentKind::Spot,
        Params::default(),
    );
    let crossed = vec![
        order(0, true, 400, 2_400_000),
        order(1, false, 400, 2_100_000),
    ];
    let s = signals(&crossed);
    let risk = RiskEngine::new(Limits::conservative_testnet());
    let pf = Portfolio {
        free_margin_micro: 1_000 * MICRO,
        ..Default::default()
    };
    let d = engine.decide(&s, &crossed, &pf, &risk, &RiskContext::healthy_at(4_000), 1);

    if let Some(approved) = &d.approved {
        assert!(risk
            .evaluate(approved.get(), &pf, &RiskContext::healthy_at(4_000))
            .is_ok());
    }
    // Oversized candidates on a crossed book must still be refused.
    let refused = d
        .candidates
        .iter()
        .filter(|c| {
            c.rejection_reason
                .as_deref()
                .is_some_and(|r| r.contains("risk refused"))
        })
        .count();
    assert!(refused > 0, "crossed book bypassed the risk gate entirely");
}
