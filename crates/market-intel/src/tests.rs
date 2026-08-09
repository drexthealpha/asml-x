//! Task 4.1.4 and 4.1.5. Signals are measured, and each has a test that fails when
//! the estimator is fed shuffled or degenerate input. An estimator that scores the
//! same on noise is noise.

use super::*;

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

fn snap(orders: Vec<OrderView>, ts_ms: u64) -> VenueSnapshot {
    VenueSnapshot {
        orders,
        block_number: 100,
        chain_time_ms: ts_ms,
    }
}

#[test]
fn best_bid_and_ask_come_from_the_right_sides() {
    let mut mi = MarketIntel::new(32);
    let s = mi.observe(
        &snap(
            vec![
                order(0, true, 5, 98),   // bid 98
                order(1, true, 5, 99),   // bid 99, better
                order(2, false, 5, 101), // ask 101, better
                order(3, false, 5, 102), // ask 102
            ],
            1_000,
        ),
        1_000,
    );
    assert_eq!(s.best_bid, Some(99 * MICRO));
    assert_eq!(s.best_ask, Some(101 * MICRO));
    assert_eq!(s.mid, Some(100 * MICRO));
    assert_eq!(s.live_order_count, 4);
}

#[test]
fn spread_is_in_basis_points_of_mid() {
    let mut mi = MarketIntel::new(32);
    let s = mi.observe(
        &snap(vec![order(0, true, 5, 99), order(1, false, 5, 101)], 0),
        0,
    );
    // spread 2 on mid 100 is 200 bps
    assert_eq!(s.spread_bps.unwrap().value, 200);
}

#[test]
fn cancelled_and_fully_filled_orders_do_not_count_as_depth() {
    let mut mi = MarketIntel::new(32);
    let mut cancelled = order(0, true, 5, 99);
    cancelled.cancelled = true;
    let mut filled = order(1, false, 5, 101);
    filled.filled_base = filled.size_base;

    let s = mi.observe(&snap(vec![cancelled, filled, order(2, true, 3, 98)], 0), 0);
    assert_eq!(s.live_order_count, 1);
    assert_eq!(s.bid_depth_base, 3 * MICRO);
    assert_eq!(s.ask_depth_base, 0);
    // Only one side is live, so there is no spread to report.
    assert!(s.spread_bps.is_none());
}

#[test]
fn an_unknown_signal_is_none_never_zero() {
    // The distinction that stops the decision engine treating "no information" as
    // "no spread" and quoting into a book it cannot see.
    let mut mi = MarketIntel::new(32);
    let s = mi.observe(&snap(vec![], 0), 0);
    assert!(s.spread_bps.is_none());
    assert!(s.mid.is_none());
    assert!(s.imbalance_bps.is_none());
    assert!(s.realized_vol_bps.is_none());
    assert_eq!(s.bid_depth_base, 0);
}

#[test]
fn imbalance_signs_correctly_and_is_bounded() {
    let mut mi = MarketIntel::new(32);
    let s = mi.observe(
        &snap(vec![order(0, true, 9, 99), order(1, false, 1, 101)], 0),
        0,
    );
    let imb = s.imbalance_bps.unwrap();
    // 9 vs 1 out of 10 total is +8000 bps.
    assert_eq!(imb.value, 8_000);
    assert!(imb.value.abs() <= 10_000);
}

#[test]
fn volatility_needs_at_least_three_observations() {
    let mut mi = MarketIntel::new(32);
    let book = vec![order(0, true, 5, 99), order(1, false, 5, 101)];
    assert!(mi
        .observe(&snap(book.clone(), 0), 0)
        .realized_vol_bps
        .is_none());
    assert!(mi
        .observe(&snap(book.clone(), 1_000), 1_000)
        .realized_vol_bps
        .is_none());
    // Third observation makes two returns available.
    assert!(mi
        .observe(&snap(book, 2_000), 2_000)
        .realized_vol_bps
        .is_some());
}

#[test]
fn volatility_is_zero_on_a_flat_series_and_positive_on_a_moving_one() {
    // R7 in spirit: the estimator must respond to the thing it claims to measure.
    let mut flat = MarketIntel::new(32);
    for t in 0..6 {
        flat.observe(
            &snap(
                vec![order(0, true, 5, 99), order(1, false, 5, 101)],
                t * 1_000,
            ),
            t * 1_000,
        );
    }
    assert_eq!(flat.realized_vol_bps().unwrap().value, 0);

    let mut moving = MarketIntel::new(32);
    for (t, p) in [(0u64, 100i128), (1, 110), (2, 95), (3, 120), (4, 90)] {
        moving.observe(
            &snap(
                vec![order(0, true, 5, p - 1), order(1, false, 5, p + 1)],
                t * 1_000,
            ),
            t * 1_000,
        );
    }
    let v = moving.realized_vol_bps().unwrap();
    assert!(v.value > 0, "moving series must show non-zero volatility");
}

#[test]
fn shuffled_input_changes_the_volatility_estimate() {
    // The anti-decoration test. If reordering the series left the estimate
    // unchanged, the estimator would not be measuring path behaviour at all and
    // would be deleted per R7.
    let ordered = [100i128, 101, 102, 103, 104, 105];
    let shuffled = [100i128, 105, 101, 104, 102, 103];

    let mut a = MarketIntel::new(32);
    for (t, p) in ordered.iter().enumerate() {
        a.observe(
            &snap(
                vec![order(0, true, 5, p - 1), order(1, false, 5, p + 1)],
                t as u64 * 1_000,
            ),
            t as u64 * 1_000,
        );
    }
    let mut b = MarketIntel::new(32);
    for (t, p) in shuffled.iter().enumerate() {
        b.observe(
            &snap(
                vec![order(0, true, 5, p - 1), order(1, false, 5, p + 1)],
                t as u64 * 1_000,
            ),
            t as u64 * 1_000,
        );
    }
    assert_ne!(
        a.realized_vol_bps().unwrap().value,
        b.realized_vol_bps().unwrap().value,
        "estimator is insensitive to ordering, so it is measuring nothing"
    );
}

#[test]
fn confidence_narrows_as_the_book_thickens() {
    let mut thin = MarketIntel::new(32);
    let s_thin = thin.observe(
        &snap(vec![order(0, true, 5, 99), order(1, false, 5, 101)], 0),
        0,
    );
    let mut thick = MarketIntel::new(32);
    let mut book = vec![];
    for i in 0..10 {
        book.push(order(i, true, 5, 99));
        book.push(order(i + 100, false, 5, 101));
    }
    let s_thick = thick.observe(&snap(book, 0), 0);

    assert!(
        s_thick.spread_bps.unwrap().confidence_halfwidth
            < s_thin.spread_bps.unwrap().confidence_halfwidth,
        "a thicker book must produce a tighter interval"
    );
    assert!(s_thick.spread_bps.unwrap().sample_size > s_thin.spread_bps.unwrap().sample_size);
}

#[test]
fn history_is_bounded_so_a_long_run_cannot_grow_without_limit() {
    let mut mi = MarketIntel::new(5);
    for t in 0..50 {
        mi.observe(
            &snap(
                vec![order(0, true, 5, 99), order(1, false, 5, 101)],
                t * 100,
            ),
            t * 100,
        );
    }
    assert_eq!(mi.history_len(), 5);
}

#[test]
fn stale_inputs_are_reported_and_collapse_thesis_confidence() {
    let mut mi = MarketIntel::new(32);
    // Chain time 0, wall-equivalent now 30s later.
    let s = mi.observe(
        &snap(vec![order(0, true, 5, 99), order(1, false, 5, 101)], 0),
        30_000,
    );
    assert_eq!(s.input_age_ms, 30_000);
    let (text, confidence) = MarketIntel::thesis(&s);
    assert!(
        text.contains("30000 ms old"),
        "thesis must disclose staleness: {text}"
    );
    assert!(
        confidence < 5_000,
        "stale inputs must collapse confidence, got {confidence}"
    );
}

#[test]
fn thesis_is_derived_from_the_numbers_not_templated() {
    let mut wide = MarketIntel::new(32);
    for t in 0..5 {
        wide.observe(
            &snap(
                vec![order(0, true, 5, 90), order(1, false, 5, 110)],
                t * 1_000,
            ),
            t * 1_000,
        );
    }
    let s = wide.observe(
        &snap(vec![order(0, true, 5, 90), order(1, false, 5, 110)], 5_000),
        5_000,
    );
    let (text, _) = MarketIntel::thesis(&s);
    // Flat mid means zero volatility, and a 2000 bps spread, so the thesis must
    // reach the "paid for the risk" conclusion rather than any other branch.
    assert!(
        text.contains("more than twice realized volatility"),
        "unexpected thesis: {text}"
    );

    let mut empty = MarketIntel::new(32);
    let s2 = empty.observe(&snap(vec![], 0), 0);
    let (text2, conf2) = MarketIntel::thesis(&s2);
    assert!(
        text2.contains("one-sided or empty"),
        "unexpected thesis: {text2}"
    );
    assert_eq!(conf2, 0);
}

/// Found by looking at the live UI: the simulator posted a bid above the resting ask, so
/// the book was crossed and the spread came out at -1333 bps. A negative spread flowed
/// into the crossing cost as a CREDIT, paying the agent to trade. A crossed book must be
/// disclosed, never monetised.
#[test]
fn a_crossed_book_is_disclosed_in_the_thesis() {
    let mut mi = MarketIntel::new(32);
    // bid 3.0 above ask 2.0: crossed.
    let s = mi.observe(
        &snap(vec![order(0, true, 5, 3), order(1, false, 5, 2)], 0),
        0,
    );
    assert!(s.best_bid.unwrap() > s.best_ask.unwrap());
    assert!(
        s.spread_bps.unwrap().value < 0,
        "a crossed book has a negative spread"
    );

    let (text, confidence) = MarketIntel::thesis(&s);
    assert!(
        text.contains("BOOK IS CROSSED"),
        "crossing not disclosed: {text}"
    );
    assert_eq!(confidence, 0, "a crossed book must not carry confidence");
}

#[test]
fn an_uncrossed_book_says_nothing_about_crossing() {
    let mut mi = MarketIntel::new(32);
    let s = mi.observe(
        &snap(vec![order(0, true, 5, 99), order(1, false, 5, 101)], 0),
        0,
    );
    let (text, _) = MarketIntel::thesis(&s);
    assert!(!text.contains("CROSSED"), "false crossing report: {text}");
}

#[test]
fn the_wei_to_micro_bridge_is_exact_and_truncating() {
    // Regression test for the bug that made the first live run refuse 10 of 11
    // candidates every cycle: 18-decimal chain values fed to a 6-decimal risk
    // engine look about 1e24 times too large, and the agent looks merely cautious.
    assert_eq!(wei_to_micro(1_000_000_000_000_000_000), MICRO); // 1.0 token
    assert_eq!(wei_to_micro(2_100_000_000_000_000_000), 2_100_000); // 2.1 tokens
    assert_eq!(micro_to_wei(MICRO), 1_000_000_000_000_000_000);
    // Truncating, not rounding, so a size can never grow past a risk check.
    // Anything below one micro-unit collapses to zero.
    assert_eq!(wei_to_micro(999_999_999_999), 0);
    // One micro plus dust keeps the micro and drops the dust.
    assert_eq!(wei_to_micro(1_999_999_999_999), 1);
    assert_eq!(micro_to_wei(wei_to_micro(1_999_999_999_999)), WEI_PER_MICRO);
}

#[test]
fn a_realistic_chain_scale_order_produces_a_sane_notional() {
    // 3 tokens at 2.1 quote each must read as 6.3 quote of notional, not 6.3e24.
    let o = OrderView {
        id: 0,
        maker_buys_base: false,
        size_base: wei_to_micro(3_000_000_000_000_000_000),
        price_quote: wei_to_micro(2_100_000_000_000_000_000),
        filled_base: 0,
        cancelled: false,
    };
    let notional = (o.size_base * o.price_quote) / MICRO;
    assert_eq!(
        notional, 6_300_000,
        "expected 6.3 in micro units, got {notional}"
    );
    assert_eq!(fmt_micro(notional), "6.300000");
}

#[test]
fn fmt_micro_is_exact() {
    assert_eq!(fmt_micro(MICRO), "1.000000");
    assert_eq!(fmt_micro(1_500_000), "1.500000");
    assert_eq!(fmt_micro(-2_250_000), "-2.250000");
    assert_eq!(fmt_micro(1), "0.000001");
}
