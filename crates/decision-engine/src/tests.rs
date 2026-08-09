//! Task 4.2 tests, including the anti-fake-win guards for this phase.

use super::*;
use market_intel::{MarketIntel, OrderView, VenueSnapshot};
use proptest::prelude::*;

fn order(id: u64, buys_base: bool, size: i128, price: i128) -> OrderView {
    OrderView {
        id,
        maker_buys_base: buys_base,
        size_base: size * MICRO,
        price_quote: price * MICRO,
        filled_base: 0,
        cancelled: false,
    }
}

fn engine() -> DecisionEngine {
    DecisionEngine::new(
        MarketId::new("tBASE/tQUOTE"),
        InstrumentKind::Spot,
        Params::default(),
    )
}

fn book_two_sided() -> Vec<OrderView> {
    vec![order(0, true, 10, 98), order(1, false, 10, 102)]
}

/// Build signals by actually running the estimator, never by hand-constructing a
/// Signals struct. A test that fabricates its inputs proves nothing about the path
/// the runtime takes.
fn signals_from(book: &[OrderView], ticks: u64) -> Signals {
    let mut mi = MarketIntel::new(32);
    let mut s = Signals::default();
    for t in 0..ticks.max(1) {
        s = mi.observe(
            &VenueSnapshot {
                orders: book.to_vec(),
                block_number: 100 + t,
                chain_time_ms: t * 1_000,
            },
            t * 1_000,
        );
    }
    s
}

fn portfolio(free: i128) -> Portfolio {
    Portfolio {
        free_margin_micro: free * MICRO,
        ..Default::default()
    }
}

#[test]
fn a_decision_always_evaluates_more_than_one_candidate() {
    // THE anti-fake-win guard for Phase 4. If this ever passes with 1, the AI claim
    // collapses into an if/else ladder.
    let e = engine();
    let book = book_two_sided();
    let s = signals_from(&book, 4);
    let d = e.decide(
        &s,
        &book,
        &portfolio(1_000),
        &RiskEngine::new(default_limits()),
        &RiskContext::healthy_at(4_000),
        1,
    );
    assert!(
        d.candidates.len() > 1,
        "only {} candidates",
        d.candidates.len()
    );
    assert!(assert_real_search(&d).is_ok());
}

#[test]
fn the_candidate_set_grows_with_the_book_so_it_is_generated_not_fixed() {
    let e = engine();
    let small = book_two_sided();
    let mut large = small.clone();
    for i in 2..8 {
        large.push(order(i, i % 2 == 0, 10, 98 + i as i128));
    }
    let ns = e.generate(&signals_from(&small, 4), &small).len();
    let nl = e.generate(&signals_from(&large, 4), &large).len();
    assert!(
        nl > ns,
        "candidate count did not grow with the book: {ns} then {nl}"
    );
}

#[test]
fn hold_is_always_a_candidate_and_can_win() {
    let e = engine();
    // A book with a negative spread relative to volatility makes acting unattractive.
    let mut mi = MarketIntel::new(32);
    let mut s = Signals::default();
    for (t, p) in [(0u64, 100i128), (1, 130), (2, 70), (3, 140), (4, 60)] {
        s = mi.observe(
            &VenueSnapshot {
                orders: vec![order(0, true, 10, p), order(1, false, 10, p + 1)],
                block_number: 100 + t,
                chain_time_ms: t * 1_000,
            },
            t * 1_000,
        );
    }
    let book = vec![order(0, true, 10, 60), order(1, false, 10, 61)];
    let d = e.decide(
        &s,
        &book,
        &portfolio(1_000),
        &RiskEngine::new(default_limits()),
        &RiskContext::healthy_at(4_000),
        1,
    );
    assert!(d.candidates.iter().any(|c| c.action == Action::Hold));
    // Under high volatility and a one-tick spread, holding should outscore taking.
    assert_eq!(
        d.chosen().map(|c| c.action.clone()),
        Some(Action::Hold),
        "expected hold to win under high volatility, scores: {:?}",
        d.candidates
            .iter()
            .map(Candidate::score_micro)
            .collect::<Vec<_>>()
    );
}

#[test]
fn every_rejected_candidate_carries_a_reason() {
    let e = engine();
    let book = book_two_sided();
    let s = signals_from(&book, 4);
    let d = e.decide(
        &s,
        &book,
        &portfolio(1_000),
        &RiskEngine::new(default_limits()),
        &RiskContext::healthy_at(4_000),
        1,
    );
    let records = d.records();
    let chosen: Vec<_> = records.iter().filter(|r| r.chosen).collect();
    assert_eq!(chosen.len(), 1, "exactly one candidate must be chosen");
    for r in records.iter().filter(|r| !r.chosen) {
        assert!(
            r.rejection_reason.is_some(),
            "candidate {} has no rejection reason",
            r.label
        );
    }
}

#[test]
fn score_terms_are_kept_separately_so_the_journal_can_explain_why() {
    let e = engine();
    let book = book_two_sided();
    let s = signals_from(&book, 4);
    let cands = e.generate(&s, &book);
    let taking: Vec<_> = cands.iter().filter(|c| c.action != Action::Hold).collect();
    assert!(!taking.is_empty());
    for c in taking {
        // A candidate whose four terms are all zero carries no information and
        // would make the scoring cosmetic.
        let terms = [
            c.expected_edge_micro,
            c.variance_penalty_micro,
            c.capital_cost_micro,
            c.execution_risk_penalty_micro,
        ];
        assert!(
            terms.iter().any(|t| *t != 0),
            "all score terms zero for {}",
            c.action.label()
        );
        assert_eq!(
            c.score_micro(),
            c.expected_edge_micro
                - c.variance_penalty_micro
                - c.capital_cost_micro
                - c.execution_risk_penalty_micro
        );
    }
}

#[test]
fn low_confidence_shrinks_size_rather_than_being_ignored() {
    let e = engine();
    // A single order gives a one-sided book, so no spread and zero confidence.
    let thin = vec![order(0, false, 10, 100)];
    let thin_signals = signals_from(&thin, 4);
    assert!(thin_signals.spread_bps.is_none());

    let thick = book_two_sided();
    let thick_signals = signals_from(&thick, 4);
    assert!(thick_signals.spread_bps.is_some());

    let thin_max = e
        .generate(&thin_signals, &thin)
        .iter()
        .filter_map(|c| match c.action {
            Action::Take { base_amount, .. } => Some(base_amount),
            _ => None,
        })
        .max()
        .unwrap_or(0);
    let thick_max = e
        .generate(&thick_signals, &thick)
        .iter()
        .filter_map(|c| match c.action {
            Action::Take { base_amount, .. } => Some(base_amount),
            _ => None,
        })
        .max()
        .unwrap_or(0);

    assert!(
        thin_max < thick_max,
        "zero-confidence book produced size {thin_max}, confident book {thick_max}"
    );
}

#[test]
fn a_killed_risk_engine_halts_the_decision_and_says_so() {
    let e = engine();
    let book = book_two_sided();
    let s = signals_from(&book, 4);
    let mut ctx = RiskContext::healthy_at(4_000);
    ctx.manual_kill = true;
    let d = e.decide(
        &s,
        &book,
        &portfolio(1_000),
        &RiskEngine::new(default_limits()),
        &ctx,
        1,
    );
    assert!(d.approved.is_none());
    assert!(
        d.risk_verdict.contains("halted"),
        "verdict was {}",
        d.risk_verdict
    );
}

#[test]
fn risk_refusal_on_the_top_candidate_does_not_end_the_search() {
    // A big candidate gets refused for size, and a smaller one should still be
    // found. Without this behaviour, one oversized idea would stall the agent.
    //
    // The book must be TWO-SIDED. A one-sided book yields no spread, so confidence
    // is zero, the size-shrink divides every candidate down to a fraction, and
    // nothing is large enough to refuse. That is correct behaviour and it made the
    // first version of this test assert something the engine never had to do.
    let e = engine();
    let book = vec![order(0, true, 400, 98), order(1, false, 400, 102)];
    let s = signals_from(&book, 4);
    let d = e.decide(
        &s,
        &book,
        &portfolio(1_000),
        &RiskEngine::new(default_limits()),
        &RiskContext::healthy_at(4_000),
        1,
    );
    let refused = d
        .candidates
        .iter()
        .filter(|c| {
            c.rejection_reason
                .as_deref()
                .is_some_and(|r| r.contains("risk refused"))
        })
        .count();
    assert!(
        refused > 0,
        "expected at least one risk refusal in the record"
    );
    assert!(d.chosen_index.is_some(), "search gave up after a refusal");
}

#[test]
fn the_naive_baseline_is_a_real_runnable_mode() {
    let b = NaiveBaseline {
        fixed_base_amount: 2 * MICRO,
        market: MarketId::new("tBASE/tQUOTE"),
        kind: InstrumentKind::Spot,
    };
    let book = book_two_sided();
    let intent = b
        .decide(&book, 1)
        .expect("baseline should act on a live book");
    assert_eq!(intent.size_micro, 2 * MICRO);
    // Empty book means no action, not a panic.
    assert!(b.decide(&[], 2).is_none());
}

#[test]
fn the_baseline_and_the_engine_actually_differ() {
    // If these agreed on every book, the comparison in task 4.3 would be theatre.
    let e = engine();
    let b = NaiveBaseline {
        fixed_base_amount: 2 * MICRO,
        market: MarketId::new("tBASE/tQUOTE"),
        kind: InstrumentKind::Spot,
    };
    let mut differences = 0;
    for spread in [1i128, 5, 20, 60] {
        let book = vec![
            order(0, true, 10, 100 - spread),
            order(1, false, 10, 100 + spread),
        ];
        let s = signals_from(&book, 5);
        let d = e.decide(
            &s,
            &book,
            &portfolio(1_000),
            &RiskEngine::new(default_limits()),
            &RiskContext::healthy_at(5_000),
            1,
        );
        let engine_size = match d.chosen().map(|c| c.action.clone()) {
            Some(Action::Take { base_amount, .. }) => base_amount,
            _ => 0,
        };
        let baseline_size = b.decide(&book, 1).map_or(0, |i| i.size_micro);
        if engine_size != baseline_size {
            differences += 1;
        }
    }
    assert!(
        differences > 0,
        "engine never diverged from the naive baseline"
    );
}

proptest! {
    /// Whatever the book, the engine never proposes something the risk engine
    /// would refuse. The gate is upstream of the action, always.
    #[test]
    fn approved_actions_always_satisfy_the_risk_engine(
        sizes in prop::collection::vec(1i128..50, 1..6),
        prices in prop::collection::vec(1i128..50, 1..6),
        free in 0i128..500,
    ) {
        let e = engine();
        let n = sizes.len().min(prices.len());
        let book: Vec<OrderView> = (0..n)
            .map(|i| order(i as u64, i % 2 == 0, sizes[i], prices[i]))
            .collect();
        let s = signals_from(&book, 4);
        let pf = portfolio(free);
        let risk = RiskEngine::new(default_limits());
        let ctx = RiskContext::healthy_at(4_000);
        let d = e.decide(&s, &book, &pf, &risk, &ctx, 1);

        if let Some(approved) = &d.approved {
            // Re-running the gate on the approved intent must agree.
            prop_assert!(risk.evaluate(approved.get(), &pf, &ctx).is_ok());
        }
        prop_assert!(!d.candidates.is_empty());
        // Exactly one chosen, or none at all when everything was refused.
        let chosen = d.records().iter().filter(|r| r.chosen).count();
        prop_assert!(chosen <= 1);
    }

    /// Scoring is deterministic. Same inputs, same ranking.
    #[test]
    fn ranking_is_deterministic(
        sizes in prop::collection::vec(1i128..40, 1..5),
        prices in prop::collection::vec(1i128..40, 1..5),
    ) {
        let e = engine();
        let n = sizes.len().min(prices.len());
        let book: Vec<OrderView> = (0..n)
            .map(|i| order(i as u64, i % 2 == 0, sizes[i], prices[i]))
            .collect();
        let s = signals_from(&book, 4);
        let a: Vec<i128> = e.generate(&s, &book).iter().map(Candidate::score_micro).collect();
        let b: Vec<i128> = e.generate(&s, &book).iter().map(Candidate::score_micro).collect();
        prop_assert_eq!(a, b);
    }
}
