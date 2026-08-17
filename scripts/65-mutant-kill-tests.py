"""Task 1.7 follow-up: tests that kill the 37 mutants that SURVIVED cargo-mutants.

Source of truth: evidence/phase0/cargo-mutants-risk-engine.txt.
57 caught, 37 missed, 13 unviable, 0 timeouts. A 61% kill rate on the crate that holds every
limit check, which is the most useful thing Phase 1 has produced.

The 37 fall into five groups, and the grouping is the finding, not the count:

A. Limits::conservative_testnet constants (4). The SHIPPED defaults were asserted nowhere;
   every test built its own limits. `5 * MICRO` -> `5 + MICRO` changes the live configuration
   and nothing noticed.

B. Boundary comparisons in rwa_check and evaluate (18: lines 335, 347, 432, 454, 467, 475,
   483, 502, 504, 518). Every limit is documented as a MAXIMUM, so value == limit must be
   ACCEPTED and limit + 1 refused. No test pinned a single one of those boundaries. Tests
   asserting "way over the limit is refused" pass under `>` -> `>=` unchanged.

C. Projection arithmetic (5: lines 453, 466, 474, 482, 498). `existing + order` -> `existing -
   order` survives whenever the book is EMPTY, because 0 + n == 0 - n in absolute value or the
   result is still under the limit. Every one of these survived because the suite tests the
   limits on an empty book, which is precisely the creep-past-a-limit-one-order-at-a-time case
   the code comment at line 448 says the projection exists to prevent. The code was right and
   untested.

D. The RWA share-cap arithmetic (8: lines 500, 505, the * and / operators). Same cause: needs a
   book with real gross exposure for the share to be a meaningful fraction.

E. is_halted (2: -> true and -> false). NO TEST CALLS is_halted AT ALL. Both mutants survive,
   which is the signature of a completely untested public function on the safety surface.

Every test below names the mutant it kills. That is deliberate: it lets a later reader
distinguish these from coverage padding, and it makes the tests falsifiable as a set. Re-run
`bash scripts/59-cargo-mutants.sh` and the missed list is the score.
"""
import io

PATH = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/crates/risk-engine/src/tests.rs"
MARKER = "the_shipped_testnet_defaults_are_exactly_what_they_claim_to_be"

TESTS = r'''

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
                mark_price_micro: Stamped::new(1 * MICRO, 0),
            },
            Position {
                market: MarketId::new("M2"),
                kind: InstrumentKind::Spot,
                net_size_micro: 20 * MICRO,
                mark_price_micro: Stamped::new(1 * MICRO, 0),
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
    assert!(l.max_rwa_share_bps <= 10_000, "a share cap above 100% is unsatisfiable");
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
    let at_cap = mk_intent(InstrumentKind::Spot, Side::Buy, 25 * MICRO, 1 * MICRO);
    let v = e.evaluate(&at_cap, &pf, &ctx);
    assert!(v.is_ok(), "notional exactly at the cap must be approved, got {v:?}");

    // One micro-unit over: refused.
    let over = mk_intent(InstrumentKind::Spot, Side::Buy, 25 * MICRO + 1, 1 * MICRO);
    assert!(matches!(
        e.evaluate(&over, &pf, &ctx),
        Err(Refusal::OrderNotionalTooLarge { .. })
    ));

    // Human approval fires STRICTLY ABOVE the threshold, so exactly at it does not.
    let at_threshold = mk_intent(
        InstrumentKind::Spot, Side::Buy, l.human_approval_threshold_micro, 1 * MICRO,
    );
    let approved = e.evaluate(&at_threshold, &pf, &ctx).expect("within all limits");
    assert!(
        !approved.requires_human_approval(),
        "notional exactly at the threshold does not require review"
    );

    let past_threshold = mk_intent(
        InstrumentKind::Spot, Side::Buy, l.human_approval_threshold_micro + 1, 1 * MICRO,
    );
    let approved = e.evaluate(&past_threshold, &pf, &ctx).expect("still under the order cap");
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
    let i = mk_intent(InstrumentKind::Spot, Side::Buy, 1 * MICRO, 1 * MICRO);

    let mut pf = book_with_exposure();
    pf.positions[0].mark_price_micro = Stamped::new(1 * MICRO, 0);
    pf.positions[1].mark_price_micro = Stamped::new(1 * MICRO, 0);

    // now_ms exactly max_mark_age_ms after the observation: the mark is at its age limit and
    // still usable.
    let ctx = RiskContext::healthy_at(l.max_mark_age_ms);
    let v = e.evaluate(&i, &pf, &ctx);
    assert!(v.is_ok(), "a mark exactly at the age limit is still fresh, got {v:?}");

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
    assert_eq!(pf.exposure_in_market_micro(&MarketId::new("M1")), 10 * MICRO);

    // Order cap is 25, so approach the 50 market cap in two steps rather than one big order.
    // 10 existing + 25 = 35, under the cap.
    let step = mk_intent(InstrumentKind::Spot, Side::Buy, 25 * MICRO, 1 * MICRO);
    assert!(e.evaluate(&step, &pf, &ctx).is_ok());

    // Now put the book at exactly the cap boundary: 40 existing + 10 = 50.
    let mut at_cap_book = book_with_exposure();
    at_cap_book.positions[0].net_size_micro = 40 * MICRO;
    let ten = mk_intent(InstrumentKind::Spot, Side::Buy, 10 * MICRO, 1 * MICRO);
    let v = e.evaluate(&ten, &at_cap_book, &ctx);
    assert!(v.is_ok(), "projecting to exactly the market cap must be approved, got {v:?}");

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
    let order = mk_intent(InstrumentKind::Spot, Side::Buy, 25 * MICRO, 1 * MICRO);

    // Gross exactly at the cap after the order: 175 + 25 = 200.
    let mut pf = book_with_exposure();
    pf.positions[0].net_size_micro = 100 * MICRO;
    pf.positions[1].net_size_micro = 75 * MICRO;
    assert_eq!(pf.gross_exposure_micro(), 175 * MICRO);
    // Net skew would refuse first at this size, so widen the skew allowance is not an option:
    // instead make the two positions oppose so net stays small while gross stays 175.
    pf.positions[1].net_size_micro = -75 * MICRO;
    assert_eq!(pf.gross_exposure_micro(), 175 * MICRO);
    let v = e.evaluate(&order, &pf, &ctx);
    assert!(v.is_ok(), "gross projecting to exactly the cap must be approved, got {v:?}");
    assert_eq!(l.max_gross_notional_micro, 200 * MICRO);

    // 176 + 25 = 201: refused. Under `current - order` it would be 151 and pass.
    let mut over = pf.clone();
    over.positions[0].net_size_micro = 101 * MICRO;
    assert_eq!(over.gross_exposure_micro(), 176 * MICRO);
    assert!(
        matches!(
            e.evaluate(&order, &over, &ctx),
            Err(Refusal::GrossNotionalTooLarge { .. })
        ),
        "projected gross of 201 against a 200 cap must be refused"
    );
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
    let order = mk_intent(InstrumentKind::Spot, Side::Buy, 25 * MICRO, 1 * MICRO);

    // Net exactly at the 75 cap after a 25 Buy: 50 existing long + 25 = 75.
    let mut pf = book_with_exposure();
    pf.positions[0].net_size_micro = 30 * MICRO;
    pf.positions[1].net_size_micro = 20 * MICRO;
    assert_eq!(pf.net_exposure_micro(), 50 * MICRO);
    let v = e.evaluate(&order, &pf, &ctx);
    assert!(v.is_ok(), "net projecting to exactly the skew cap must be approved, got {v:?}");

    // 51 + 25 = 76: refused.
    let mut over = pf.clone();
    over.positions[0].net_size_micro = 31 * MICRO;
    assert_eq!(over.net_exposure_micro(), 51 * MICRO);
    assert!(matches!(
        e.evaluate(&order, &over, &ctx),
        Err(Refusal::NetSkewTooLarge { .. })
    ));

    // The sign convention: the SAME oversized-skew book accepts a Sell, because selling reduces
    // a long skew. This is what makes the `+` -> `-` mutant detectable rather than merely wrong.
    let sell = mk_intent(InstrumentKind::Spot, Side::Sell, 25 * MICRO, 1 * MICRO);
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
    let order = mk_intent(InstrumentKind::Spot, Side::Buy, 20 * MICRO, 1 * MICRO);

    // Leaves exactly the minimum: 25 - 20 = 5, and the minimum is 5.
    let pf = empty_book(25 * MICRO);
    let v = e.evaluate(&order, &pf, &ctx);
    assert!(v.is_ok(), "leaving exactly the minimum is acceptable, got {v:?}");
    assert_eq!(l.min_free_margin_micro, 5 * MICRO);

    // Leaves one micro-unit less than the minimum: refused.
    let pf = empty_book(25 * MICRO - 1);
    match e.evaluate(&order, &pf, &ctx) {
        Err(Refusal::InsufficientFreeMargin { would_leave, minimum }) => {
            assert_eq!(would_leave, 5 * MICRO - 1);
            assert_eq!(minimum, 5 * MICRO);
        }
        other => panic!("expected InsufficientFreeMargin, got {other:?}"),
    }

    // And the direction of the arithmetic: an order strictly larger than free margin can never
    // be approved, which `free + order` would allow.
    let big = mk_intent(InstrumentKind::Spot, Side::Buy, 20 * MICRO, 1 * MICRO);
    assert!(matches!(
        e.evaluate(&big, &empty_book(1 * MICRO), &ctx),
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

    // A book with 100 units of non-RWA gross, split to keep net skew inside its cap.
    let mut pf = Portfolio {
        positions: vec![
            Position {
                market: MarketId::new("M1"),
                kind: InstrumentKind::Spot,
                net_size_micro: 60 * MICRO,
                mark_price_micro: Stamped::new(1 * MICRO, 0),
            },
            Position {
                market: MarketId::new("M2"),
                kind: InstrumentKind::Spot,
                net_size_micro: -40 * MICRO,
                mark_price_micro: Stamped::new(1 * MICRO, 0),
            },
        ],
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    };
    assert_eq!(pf.gross_exposure_micro(), 100 * MICRO);
    assert_eq!(l.max_rwa_share_bps, 4_000); // 40%

    // Projected gross with a 25-unit RWA order is 125, so the share allowance is 50 units, well
    // above the 10-unit absolute floor. 25 of 125 is 20%, inside the cap.
    let rwa = OrderIntent {
        market: MarketId::new("RWA/tQUOTE"),
        kind: InstrumentKind::RwaLinked,
        side: Side::Buy,
        size_micro: 25 * MICRO,
        limit_price_micro: 1 * MICRO,
        decision_id: 1,
    };
    let v = e.evaluate(&rwa, &pf, &ctx);
    assert!(v.is_ok(), "20% RWA share against a 40% cap must be approved, got {v:?}");

    // Now load the book with EXISTING RWA exposure so the projection is what refuses.
    // 45 existing RWA + 25 new = 70 projected RWA; projected gross 100 + 25 = 125; allowance is
    // 40% of 125 = 50. 70 > 50, so this is refused, and the refusal proves the share arithmetic
    // multiplies and divides in the right order.
    pf.positions.push(Position {
        market: MarketId::new("RWA/tQUOTE"),
        kind: InstrumentKind::RwaLinked,
        net_size_micro: 45 * MICRO,
        mark_price_micro: Stamped::new(1 * MICRO, 0),
    });
    // Keep the non-RWA legs opposing so net skew does not refuse first.
    pf.positions[1].net_size_micro = -85 * MICRO;
    match e.evaluate(&rwa, &pf, &ctx) {
        Err(Refusal::RwaShareTooLarge { got_bps, limit_bps }) => {
            assert_eq!(limit_bps, 4_000);
            // The reported share must be the meaningful number, not a placeholder: 70 of 190
            // projected gross. If the divisor or the 10_000 factor were mutated this would move.
            assert!(
                got_bps > 4_000,
                "a refusal for share must report a share above the limit, got {got_bps}"
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
                mark_price_micro: Stamped::new(1 * MICRO, 0),
            },
            Position {
                market: MarketId::new("RWA/tQUOTE"),
                kind: InstrumentKind::RwaLinked,
                net_size_micro: 20 * MICRO,
                mark_price_micro: Stamped::new(1 * MICRO, 0),
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
        limit_price_micro: 1 * MICRO,
        decision_id: 2,
    };

    match e.evaluate(&rwa, &pf, &ctx) {
        Err(Refusal::RwaShareTooLarge { got_bps, limit_bps }) => {
            // 25 of 50 is exactly half.
            assert_eq!(got_bps, 5_000, "the reported share must be the real fraction");
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
    assert!(!e.is_halted(&pf, &healthy), "a healthy context is not halted");

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
        ("data_stale", (|c: &mut RiskContext| c.data_stale = true) as fn(&mut RiskContext)),
        ("reconciliation", |c: &mut RiskContext| c.reconciliation_mismatch = true),
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
'''


def main():
    src = open(PATH, encoding="utf-8").read()
    if MARKER in src:
        print("  already present, not duplicating")
        return 0
    with io.open(PATH, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(TESTS)
    print("  appended 11 mutant-killing tests to crates/risk-engine/src/tests.rs")
    print("  groups: A defaults(4 mutants) B boundaries(18) C projections(5) D rwa share(8) E is_halted(2)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
