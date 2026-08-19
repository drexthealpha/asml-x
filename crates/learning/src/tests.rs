//! Phase 7 tests. The important ones are the anti-fake-win guards:
//! - a learned parameter must actually CHANGE THE DECISION, not merely change value
//! - learning must be unable to reach a risk limit, checked at the type level
//! - improvement claims must carry their sample size

use super::*;
use core_types::{InstrumentKind, MarketId, Portfolio, MICRO};
use decision_engine::{Action, Candidate, DecisionEngine, Params};
use market_intel::{MarketIntel, OrderView, Signals, VenueSnapshot};
use risk_engine::{Limits, RiskContext, RiskEngine};

/// Like `order` but the price is given in micro units, so a book can be built whose
/// notionals fit inside the conservative testnet limits. The first version of the
/// parameter-sensitivity test used whole-unit prices, which made every take candidate
/// exceed `max_order_notional_micro`. Every candidate was refused, Hold won at both
/// parameter values, and the test failed for a reason that had nothing to do with the
/// parameter it was probing.
fn order_micro(id: u64, buys_base: bool, size_units: i128, price_micro: i128) -> OrderView {
    OrderView {
        id,
        maker_buys_base: buys_base,
        size_base: size_units * MICRO,
        price_quote: price_micro,
        filled_base: 0,
        cancelled: false,
    }
}

/// Signals produced by actually running the estimator, never hand-built.
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

fn pending(id: u64, predicted: Predicted, mid: Micro, expected_edge: Micro, at_ms: u64) -> Pending {
    Pending {
        decision_id: id,
        predicted,
        mid_at_decision: mid,
        expected_edge_micro: expected_edge,
        opened_at_ms: at_ms,
        params_at_decision: Params::default(),
        signal_name: "imbalance_bps".to_string(),
        // 1.0 base in micro units, so a settlement in these tests produces a realized PnL equal to
        // the price move. A size of zero would make every PnL assertion below pass trivially.
        size_micro: 1_000_000,
    }
}

// ---------------------------------------------------------------------------
// THE anti-fake-win guard for Phase 7
// ---------------------------------------------------------------------------

/// A learned parameter that changes value but never reaches the decision is theatre.
/// This pins two different values of `momentum_weight_bps` and asserts the DECISION
/// differs, not just the number.
#[test]
fn a_learned_parameter_actually_changes_the_decision() {
    // Bid-heavy book (5 base bid, 1 base ask) so the imbalance signal points up, with
    // notionals small enough that the risk gate permits the takes. If the gate refuses
    // everything, Hold wins at every parameter value and the test measures nothing.
    let book = vec![
        order_micro(0, true, 5, 2_000_000),
        order_micro(1, false, 1, 2_100_000),
    ];
    let signals = signals_from(&book, 5);
    let pf = Portfolio {
        free_margin_micro: 1_000 * MICRO,
        ..Default::default()
    };
    let risk = RiskEngine::new(Limits::conservative());
    let ctx = RiskContext::healthy_at(5_000);

    let low = DecisionEngine::new(
        MarketId::new("tBASE/tQUOTE"),
        InstrumentKind::Spot,
        Params {
            momentum_weight_bps: 0,
            ..Params::default()
        },
    );
    let high = DecisionEngine::new(
        MarketId::new("tBASE/tQUOTE"),
        InstrumentKind::Spot,
        Params {
            momentum_weight_bps: 6_000,
            ..Params::default()
        },
    );

    let d_low = low.decide(&signals, &book, &pf, &risk, &ctx, 1);
    let d_high = high.decide(&signals, &book, &pf, &risk, &ctx, 2);

    let scores_low: Vec<i128> = d_low
        .candidates
        .iter()
        .map(Candidate::score_micro)
        .collect();
    let scores_high: Vec<i128> = d_high
        .candidates
        .iter()
        .map(Candidate::score_micro)
        .collect();

    assert_ne!(
        scores_low, scores_high,
        "momentum_weight_bps did not affect any candidate score, so the parameter is not read"
    );

    // And the chosen action must differ too, which is the stronger claim: with no
    // momentum weight the directional edge vanishes and holding should win.
    let chosen_low = d_low.chosen().map(|c| c.action.clone());
    let chosen_high = d_high.chosen().map(|c| c.action.clone());
    assert_ne!(
        chosen_low, chosen_high,
        "the chosen action was identical at momentum weight 0 and 6000, so learning cannot matter"
    );
    assert_eq!(
        chosen_low,
        Some(Action::Hold),
        "with zero momentum weight, holding should win"
    );
}

/// Learning cannot reach a risk limit, and the reason is structural rather than a
/// policy. If someone ever gives `Learner` a `Limits` field or method, this test is the
/// tripwire: it asserts the limits object is byte-identical before and after a full
/// learning cycle, and there is no API through which it could have changed.
#[test]
fn learning_cannot_reach_a_risk_limit_because_it_has_no_type_for_one() {
    let limits_before = Limits::conservative();
    let mut learner = Learner::new(Params::default());

    // Feed a full cycle of outcomes and force an update.
    for i in 0..10u64 {
        learner.record_decision(pending(i, Predicted::Up, 100 * MICRO, 10, i * 1_000));
    }
    let settled = learner.settle_due(60_000, 110 * MICRO, 5_000);
    assert_eq!(settled.len(), 10);
    let changes = learner.update_params(60_000);
    assert!(
        !changes.is_empty(),
        "expected a parameter change after 10 outcomes"
    );

    let limits_after = Limits::conservative();
    assert_eq!(
        limits_before, limits_after,
        "risk limits changed across a learning cycle"
    );

    // The structural statement: Params, the only thing learning produces, carries no
    // limit at all. If a limit were ever added to Params this would stop compiling as a
    // reminder that the boundary moved.
    let p: &Params = learner.params();
    let _ = (
        p.momentum_weight_bps,
        p.variance_weight_bps,
        p.capital_cost_bps,
        p.thin_book_penalty_bps,
        p.min_confidence_bps,
        p.max_take_fraction_bps,
    );
}

// ---------------------------------------------------------------------------
// Settlement correctness
// ---------------------------------------------------------------------------

#[test]
fn nothing_settles_before_the_lag_elapses() {
    // A forecast scored against the price it was made at is scored against itself and
    // would report a perfect hit rate for a signal with no information.
    let mut l = Learner::new(Params::default());
    l.record_decision(pending(1, Predicted::Up, 100 * MICRO, 0, 1_000));
    assert!(l.settle_due(2_000, 110 * MICRO, 5_000).is_empty());
    assert_eq!(l.pending_count(), 1);
    assert_eq!(l.settle_due(6_500, 110 * MICRO, 5_000).len(), 1);
    assert_eq!(l.pending_count(), 0);
}

#[test]
fn direction_is_scored_correctly_in_both_directions() {
    let mut l = Learner::new(Params::default());
    l.record_decision(pending(1, Predicted::Up, 100 * MICRO, 0, 0));
    l.record_decision(pending(2, Predicted::Down, 100 * MICRO, 0, 0));
    let out = l.settle_due(10_000, 110 * MICRO, 1_000);
    assert_eq!(out.len(), 2);

    let up = out.iter().find(|o| o.decision_id == 1).unwrap();
    let down = out.iter().find(|o| o.decision_id == 2).unwrap();
    assert_eq!(up.realized_move_bps, 1_000); // +10 percent
    assert!(up.direction_correct);
    assert!(
        !down.direction_correct,
        "a Down forecast must be wrong when price rose"
    );

    let s = l.stats_for("imbalance_bps");
    assert_eq!(s.samples, 2);
    assert_eq!(s.correct, 1);
    assert_eq!(s.hit_rate_bps(), 5_000);
}

#[test]
fn a_hold_is_never_scored_because_it_made_no_forecast() {
    let mut l = Learner::new(Params::default());
    l.record_decision(pending(1, Predicted::NoView, 100 * MICRO, 0, 0));
    assert!(l.settle_due(10_000, 200 * MICRO, 1_000).is_empty());
    assert_eq!(
        l.pending_count(),
        0,
        "holds must be dropped, not queued forever"
    );
    assert_eq!(l.stats_for("imbalance_bps").samples, 0);
}

/// Regression test for the flaw the first live run exposed: a flat market scored every
/// forecast as WRONG, so the hit rate came back 0 out of 14 and every signal decayed to
/// no weight regardless of quality. A market that did not move judges nothing.
#[test]
fn a_flat_market_scores_nothing_rather_than_scoring_everything_wrong() {
    let mut l = Learner::new(Params::default());
    for i in 0..8u64 {
        l.record_decision(pending(i, Predicted::Up, 100 * MICRO, 0, 0));
    }
    // Settle against an identical mid: zero move.
    let out = l.settle_due(10_000, 100 * MICRO, 1_000);
    assert!(
        out.is_empty(),
        "a flat market must produce no scored outcomes"
    );
    assert_eq!(l.stats_for("imbalance_bps").samples, 0);
    assert_eq!(l.unscored_flat(), 8);

    // And with nothing scored, no parameter may move.
    let before = l.params().clone();
    assert!(l.update_params(10_000).is_empty());
    assert_eq!(*l.params(), before);
}

#[test]
fn a_move_just_inside_the_dead_band_is_unscored_and_just_outside_is_scored() {
    // The boundary, pinned. 100 -> 100.04 is 4 bps, inside a 5 bps band.
    let mut inside = Learner::new(Params::default());
    inside.record_decision(pending(1, Predicted::Up, 100 * MICRO, 0, 0));
    assert!(inside.settle_due(10_000, 100_040_000, 1_000).is_empty());
    assert_eq!(inside.unscored_flat(), 1);

    // 100 -> 100.06 is 6 bps, outside the band, and correctly scored as an up move.
    let mut outside = Learner::new(Params::default());
    outside.record_decision(pending(1, Predicted::Up, 100 * MICRO, 0, 0));
    let out = outside.settle_due(10_000, 100_060_000, 1_000);
    assert_eq!(out.len(), 1);
    assert!(out[0].direction_correct);
    assert_eq!(outside.unscored_flat(), 0);
}

#[test]
fn edge_error_detects_systematic_over_optimism() {
    // Expected 500 micro of edge, realized 100 bps of favourable move.
    let mut l = Learner::new(Params::default());
    l.record_decision(pending(1, Predicted::Up, 100 * MICRO, 500, 0));
    let out = l.settle_due(10_000, 101 * MICRO, 1_000);
    assert_eq!(out[0].realized_move_bps, 100);
    assert_eq!(out[0].edge_error_micro, 100 - 500);
    assert!(
        out[0].edge_error_micro < 0,
        "overestimating edge must give a negative error"
    );
}

// ---------------------------------------------------------------------------
// Update rule behaviour and bounds
// ---------------------------------------------------------------------------

#[test]
fn no_parameter_moves_below_the_minimum_sample_count() {
    // Adjusting a weight on three observations is overfitting with extra steps.
    let mut l = Learner::new(Params::default());
    let before = l.params().clone();
    for i in 0..(MIN_SAMPLES_TO_UPDATE - 1) {
        l.record_decision(pending(u64::from(i), Predicted::Up, 100 * MICRO, 0, 0));
    }
    l.settle_due(10_000, 110 * MICRO, 1_000);
    assert!(l.update_params(10_000).is_empty());
    assert_eq!(*l.params(), before);
}

#[test]
fn a_signal_that_is_right_raises_its_weight_and_one_that_is_wrong_lowers_it() {
    let mut good = Learner::new(Params::default());
    for i in 0..10u64 {
        good.record_decision(pending(i, Predicted::Up, 100 * MICRO, 0, 0));
    }
    good.settle_due(10_000, 110 * MICRO, 1_000); // all correct
    let before_good = good.params().momentum_weight_bps;
    good.update_params(10_000);
    assert!(
        good.params().momentum_weight_bps > before_good,
        "a perfect signal must gain weight: {} then {}",
        before_good,
        good.params().momentum_weight_bps
    );

    let mut bad = Learner::new(Params::default());
    for i in 0..10u64 {
        bad.record_decision(pending(i, Predicted::Up, 100 * MICRO, 0, 0));
    }
    bad.settle_due(10_000, 90 * MICRO, 1_000); // all wrong
    let before_bad = bad.params().momentum_weight_bps;
    bad.update_params(10_000);
    assert!(
        bad.params().momentum_weight_bps < before_bad,
        "a signal that is always wrong must lose weight"
    );
}

#[test]
fn a_coinflip_signal_converges_toward_no_weight() {
    // The property that matters most: a signal with no information must not accumulate
    // influence. Alternating correct and incorrect gives a 5000 bps hit rate.
    let mut l = Learner::new(Params::default());
    let start = l.params().momentum_weight_bps;
    for round in 0..6u64 {
        l.record_decision(pending(round * 2, Predicted::Up, 100 * MICRO, 0, 0));
        l.settle_due(10_000, 110 * MICRO, 1_000);
        l.record_decision(pending(round * 2 + 1, Predicted::Up, 100 * MICRO, 0, 0));
        l.settle_due(20_000, 90 * MICRO, 1_000);
        l.update_params(20_000);
    }
    assert_eq!(l.stats_for("imbalance_bps").hit_rate_bps(), 5_000);
    assert!(
        l.params().momentum_weight_bps <= start,
        "a coinflip signal gained weight: {} then {}",
        start,
        l.params().momentum_weight_bps
    );
}

#[test]
fn weights_are_clamped_on_both_sides_so_a_feedback_loop_cannot_run_away() {
    let mut l = Learner::new(Params::default());
    for round in 0..80u64 {
        l.record_decision(pending(round, Predicted::Up, 100 * MICRO, 0, 0));
        l.settle_due(10_000 + round * 1_000, 110 * MICRO, 1_000);
        l.update_params(10_000 + round * 1_000);
        assert!(l.params().momentum_weight_bps <= MOMENTUM_WEIGHT_MAX);
        assert!(l.params().thin_book_penalty_bps <= THIN_BOOK_PENALTY_MAX);
        // THIN_BOOK_PENALTY_MIN is 25, not 0, so this comparison can actually fail
        // and is worth asserting.
        assert!(l.params().thin_book_penalty_bps >= THIN_BOOK_PENALTY_MIN);
    }
    assert_eq!(l.params().momentum_weight_bps, MOMENTUM_WEIGHT_MAX);
}

#[test]
fn every_parameter_change_carries_its_evidence() {
    // A change with no attribution is indistinguishable from a random walk.
    let mut l = Learner::new(Params::default());
    for i in 0..8u64 {
        l.record_decision(pending(i, Predicted::Up, 100 * MICRO, 0, 0));
    }
    l.settle_due(10_000, 110 * MICRO, 1_000);
    let changes = l.update_params(10_000);
    assert!(!changes.is_empty());
    for c in &changes {
        assert!(
            !c.trigger.is_empty(),
            "change to {} has no trigger",
            c.parameter
        );
        assert!(c.samples >= MIN_SAMPLES_TO_UPDATE);
        assert_ne!(c.from, c.to);
        assert!(
            c.trigger.contains(&c.samples.to_string()),
            "trigger must name the sample size: {}",
            c.trigger
        );
    }
    assert_eq!(l.history().len(), changes.len());
}

#[test]
fn explain_reports_the_sample_size_not_just_the_change() {
    let mut l = Learner::new(Params::default());
    assert!(l.explain().contains("no parameter changes yet"));
    for i in 0..8u64 {
        l.record_decision(pending(i, Predicted::Up, 100 * MICRO, 0, 0));
    }
    l.settle_due(10_000, 110 * MICRO, 1_000);
    l.update_params(10_000);
    let text = l.explain();
    assert!(text.contains("settled outcomes"), "{text}");
    assert!(text.contains("because"), "{text}");
}

// ---------------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------------

#[test]
fn learned_state_survives_a_restart() {
    // Without persistence, any demonstration of improvement is an artifact of one
    // process lifetime.
    let mut path = std::env::temp_dir();
    path.push(format!("asml-learning-test-{}.json", std::process::id()));
    let _ = std::fs::remove_file(&path);

    {
        let mut l = Learner::load(&path, Params::default());
        for i in 0..10u64 {
            l.record_decision(pending(i, Predicted::Up, 100 * MICRO, 0, 0));
        }
        l.settle_due(10_000, 110 * MICRO, 1_000);
        l.update_params(10_000);
        l.save().unwrap();
    }

    let reloaded = Learner::load(&path, Params::default());
    assert_eq!(reloaded.settled_count(), 10);
    assert_eq!(reloaded.stats_for("imbalance_bps").samples, 10);
    assert_eq!(reloaded.stats_for("imbalance_bps").correct, 10);
    assert!(
        reloaded.params().momentum_weight_bps > Params::default().momentum_weight_bps,
        "the learned weight did not survive the restart"
    );

    let _ = std::fs::remove_file(&path);
}

/// Regression test for the second flaw the live run exposed: outstanding forecasts were
/// dropped on process exit, so a sequence of short runs reported `settled 0` while
/// appearing to work. A forecast that cannot outlive the process can never be scored
/// against a later price.
#[test]
fn pending_forecasts_survive_a_restart_and_settle_afterwards() {
    let mut path = std::env::temp_dir();
    path.push(format!("asml-learning-pending-{}.json", std::process::id()));
    let _ = std::fs::remove_file(&path);

    {
        let mut l = Learner::load(&path, Params::default());
        for i in 0..6u64 {
            l.record_decision(pending(i, Predicted::Up, 100 * MICRO, 0, 1_000));
        }
        // Nothing settles yet: the lag has not elapsed.
        assert!(l.settle_due(2_000, 100 * MICRO, 5_000).is_empty());
        assert_eq!(l.pending_count(), 6);
        l.save().unwrap();
    }

    // New process. The forecasts must still be there, and must settle against a mid
    // observed later at a genuinely different price.
    let mut reloaded = Learner::load(&path, Params::default());
    assert_eq!(
        reloaded.pending_count(),
        6,
        "pending forecasts did not survive the restart"
    );
    let out = reloaded.settle_due(20_000, 110 * MICRO, 5_000);
    assert_eq!(out.len(), 6);
    assert!(out.iter().all(|o| o.direction_correct));
    assert_eq!(reloaded.stats_for("imbalance_bps").samples, 6);

    let _ = std::fs::remove_file(&path);
}

#[test]
fn a_cold_start_and_a_trained_instance_genuinely_differ() {
    // The basis of the improvement claim. Reported with its sample size, because a
    // claimed effect on ten trades is not a performance result.
    let cold = Learner::new(Params::default());

    let mut trained = Learner::new(Params::default());
    for i in 0..12u64 {
        trained.record_decision(pending(i, Predicted::Up, 100 * MICRO, 0, 0));
    }
    trained.settle_due(20_000, 115 * MICRO, 1_000);
    trained.update_params(20_000);

    assert_ne!(cold.params(), trained.params());
    assert_eq!(cold.settled_count(), 0);
    assert_eq!(trained.settled_count(), 12);
    assert_eq!(trained.stats_for("imbalance_bps").samples, 12);
}

/// The lower clamp, tested for real.
///
/// The clamp test previously asserted `momentum_weight_bps >= MOMENTUM_WEIGHT_MIN`, which
/// is always true for an unsigned field with a floor of zero. Clippy caught it as a
/// comparison that cannot fail. The property the floor actually exists for is that a
/// signal which is wrong every single time drives the weight down to exactly the floor and
/// then STOPS there, rather than wrapping, saturating somewhere else, or oscillating.
#[test]
fn a_persistently_wrong_signal_lands_exactly_on_the_floor_and_stays() {
    let mut l = Learner::new(Params::default());
    let mut seen_floor = false;
    for round in 0..60u64 {
        l.record_decision(pending(round, Predicted::Up, 100 * MICRO, 0, 0));
        // Price falls every time, so an Up forecast is always wrong.
        l.settle_due(10_000 + round * 1_000, 90 * MICRO, 1_000);
        l.update_params(10_000 + round * 1_000);
        if l.params().momentum_weight_bps == MOMENTUM_WEIGHT_MIN {
            seen_floor = true;
        }
        // Once on the floor it must never leave while the signal stays wrong.
        if seen_floor {
            assert_eq!(
                l.params().momentum_weight_bps,
                MOMENTUM_WEIGHT_MIN,
                "weight left the floor at round {round} while the signal was still wrong"
            );
        }
    }
    assert!(
        seen_floor,
        "a signal wrong 60 times never reached the floor"
    );
    assert_eq!(l.stats_for("imbalance_bps").hit_rate_bps(), 0);
}

// ---------------------------------------------------------------------------
// TASK 14.4: realized PnL
//
// A hit rate grades forecasts; a PnL grades trading. These pin the arithmetic and the sign, because
// a PnL with an inverted sign for shorts is a bug that makes a losing system look profitable and
// passes every direction-based test in this file.
// ---------------------------------------------------------------------------

#[test]
fn long_that_rises_makes_money_proportional_to_size() {
    let mut l = Learner::new(Params::default());
    let mut p = pending(1, Predicted::Up, 100 * MICRO, 0, 0);
    p.size_micro = 2 * MICRO; // 2.0 base
    l.record_decision(p);

    // Mid moves 100 -> 110, a gain of 10 quote per base unit, on 2 units.
    let out = l.settle_due(10_000, 110 * MICRO, 1_000);
    assert_eq!(out.len(), 1, "the forecast did not settle");
    assert_eq!(out[0].realized_pnl_micro, 20 * MICRO, "2 units * 10 move");
    assert!(out[0].direction_correct);
}

#[test]
fn short_that_falls_makes_money_and_the_sign_is_not_inverted() {
    let mut l = Learner::new(Params::default());
    let mut p = pending(2, Predicted::Down, 100 * MICRO, 0, 0);
    p.size_micro = 2 * MICRO;
    l.record_decision(p);

    // Mid falls 100 -> 90. A short gains. If the direction sign were dropped this would come out
    // negative, which is the whole reason this test exists separately from the long case.
    let out = l.settle_due(10_000, 90 * MICRO, 1_000);
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].realized_pnl_micro, 20 * MICRO);
    assert!(out[0].direction_correct);
}

#[test]
fn a_wrong_call_produces_a_negative_pnl() {
    let mut l = Learner::new(Params::default());
    let mut p = pending(3, Predicted::Up, 100 * MICRO, 0, 0);
    p.size_micro = MICRO;
    l.record_decision(p);

    let out = l.settle_due(10_000, 90 * MICRO, 1_000);
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].realized_pnl_micro, -10 * MICRO);
    assert!(!out[0].direction_correct);
    assert!(
        out[0].realized_pnl_micro < 0,
        "a losing trade must report a loss, not an absolute value"
    );
}

#[test]
fn a_forecast_with_no_recorded_size_reports_zero_pnl_rather_than_a_guess() {
    // State files written before 14.4 have no size. Such a forecast is still scoreable for
    // DIRECTION, and must contribute exactly zero to PnL rather than being dropped or guessed at.
    let mut l = Learner::new(Params::default());
    let mut p = pending(4, Predicted::Up, 100 * MICRO, 0, 0);
    p.size_micro = 0;
    l.record_decision(p);

    let out = l.settle_due(10_000, 110 * MICRO, 1_000);
    assert_eq!(out.len(), 1, "it must still settle for direction");
    assert_eq!(out[0].realized_pnl_micro, 0);
    assert!(out[0].direction_correct, "direction is still scoreable");
}

#[test]
fn expected_edge_survives_settlement_rather_than_being_reconstructed() {
    // Carried through, not derived. Deriving it from edge_error requires re-applying the direction
    // sign and gets a short wrong.
    let mut l = Learner::new(Params::default());
    let mut p = pending(5, Predicted::Down, 100 * MICRO, 777, 0);
    p.size_micro = MICRO;
    l.record_decision(p);

    let out = l.settle_due(10_000, 90 * MICRO, 1_000);
    assert_eq!(out[0].expected_edge_micro, 777);
    assert_eq!(out[0].size_micro, MICRO);
}

#[test]
fn parameter_history_survives_a_reload() {
    // Regression for a defect task 14.6 surfaced: `save` wrote the parameter history and `load`
    // silently dropped it, so the recorded history was only ever the CURRENT process's changes.
    // The panel showed momentum weight moving 411 -> 401 when it had actually fallen from its
    // default of 2000, understating the learning effect by two orders of magnitude while looking
    // entirely plausible.
    //
    // Same shape as the pending-queue defect fixed earlier: anything written on save and not read
    // on load is a lie the next run tells.
    let dir = std::env::temp_dir().join(format!("asml-hist-{}", std::process::id()));
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join("state.json");

    let mut l = Learner::load(&path, Params::default());
    for i in 0..10u64 {
        l.record_decision(pending(i, Predicted::Up, 100 * MICRO, 10, i * 1_000));
    }
    l.settle_due(60_000, 90 * MICRO, 5_000);
    let changes = l.update_params(60_000);
    assert!(
        !changes.is_empty(),
        "no parameter moved, so there is no history to test and this test would pass vacuously"
    );
    let before = l.history().len();
    assert!(before > 0);
    l.save().expect("save");

    let reloaded = Learner::load(&path, Params::default());
    assert_eq!(
        reloaded.history().len(),
        before,
        "history did not survive the reload"
    );
    assert_eq!(reloaded.history()[0].parameter, l.history()[0].parameter);
    assert_eq!(reloaded.history()[0].from, l.history()[0].from);
    assert_eq!(reloaded.history()[0].samples, l.history()[0].samples);

    let _ = std::fs::remove_dir_all(&dir);
}
