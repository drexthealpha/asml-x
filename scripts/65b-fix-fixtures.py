"""Fix three of the eleven new tests. The failures were real and they were mine, not the code's.

All three failed with MarketNotionalTooLarge, and the cause is one mistake repeated: I built
large exposure by making a SINGLE market's position large, and the per-market cap (50) binds
before the gross cap (200), the net skew cap (75) or the RWA share cap can be reached. On top of
that, `mk_intent` puts every order in market "M1", so an order aimed at a loaded market projects
that market past its own cap first.

The fix is structural rather than cosmetic: spread exposure across SEVERAL markets so each stays
inside the per-market cap while gross accumulates, and send the test order into a market that is
not already loaded. This is worth stating plainly because the check ORDER matters here: a test
that wants to exercise the gross cap has to first satisfy every earlier check, otherwise it is
testing the earlier check and reporting the later one.

Recomputed arithmetic, so the numbers below are derived rather than guessed:

  gross boundary: four markets at +44, -44, +44, -43 gives gross 175 and net +1. A 25-unit order
    into a fresh market projects gross to exactly 200 (the cap) and that market to 25.
    Over case: +44, -44, +44, -44 gives gross 176, so projected gross 201, refused.

  net skew boundary: M1 +30 and M2 +20 gives net 50, gross 50. A 25-unit Buy into fresh M3
    projects net to exactly 75 (the cap), market to 25, gross to 75. Over: M1 +31 gives net 51,
    projected 76, refused. The Sell case then reduces 51 to 26 and must be allowed.

  rwa share cap: non-RWA M1 +20 and M2 -20 (gross 40, net 0), existing RWA 20. A 25-unit RWA Buy
    projects: that market 20 + 25 = 45 (inside 50), gross 60 + 25 = 85, net 20 + 25 = 45 (inside
    75), projected RWA 45. Allowance is 40% of 85 = 34, and max(34, 10) = 34. 45 > 34, so the
    SHARE cap is what refuses, which is the point of the test. Reported share is
    45 * 10000 / 85 = 5294 bps, above the 4000 limit.
"""
import re

PATH = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/crates/risk-engine/src/tests.rs"

GROSS_NEW = r'''#[test]
fn the_gross_projection_adds_to_current_gross_and_its_boundary_is_inclusive() {
    let e = engine();
    let ctx = RiskContext::healthy_at(0);
    let l = Limits::conservative();

    // FOUR markets, none above the 50 per-market cap, alternating sign so net skew stays tiny
    // while gross accumulates to 175. Building this out of one large position instead is what
    // made the first version of this test fail against the per-market cap: the earlier check
    // fires first, so the test would have been reporting on the wrong limit.
    let spread = |sizes: [i128; 4]| Portfolio {
        positions: sizes
            .iter()
            .enumerate()
            .map(|(i, s)| Position {
                market: MarketId::new(&format!("G{i}")),
                kind: InstrumentKind::Spot,
                net_size_micro: s * MICRO,
                mark_price_micro: Stamped::new(1 * MICRO, 0),
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
        limit_price_micro: 1 * MICRO,
        decision_id: 11,
    };

    let pf = spread([44, -44, 44, -43]);
    assert_eq!(pf.gross_exposure_micro(), 175 * MICRO);
    assert_eq!(l.max_gross_notional_micro, 200 * MICRO);
    let v = e.evaluate(&order, &pf, &ctx);
    assert!(v.is_ok(), "gross projecting to exactly the cap must be approved, got {v:?}");

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
}'''

NET_NEW = r'''#[test]
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
                mark_price_micro: Stamped::new(1 * MICRO, 0),
            },
            Position {
                market: MarketId::new("N2"),
                kind: InstrumentKind::Spot,
                net_size_micro: b * MICRO,
                mark_price_micro: Stamped::new(1 * MICRO, 0),
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
        limit_price_micro: 1 * MICRO,
        decision_id: 12,
    };

    // 50 existing net + 25 = exactly the 75 cap.
    let pf = book(30, 20);
    assert_eq!(pf.net_exposure_micro(), 50 * MICRO);
    let v = e.evaluate(&buy, &pf, &ctx);
    assert!(v.is_ok(), "net projecting to exactly the skew cap must be approved, got {v:?}");

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
    let sell = OrderIntent { side: Side::Sell, ..buy.clone() };
    assert!(
        e.evaluate(&sell, &over, &ctx).is_ok(),
        "a Sell against a long book reduces skew and must be allowed"
    );
}'''

RWA_NEW = r'''#[test]
fn the_rwa_share_cap_is_a_real_fraction_of_projected_gross() {
    let e = engine();
    let ctx = RiskContext::healthy_at(0).with_rwa(healthy_rwa());
    let l = Limits::conservative();
    assert_eq!(l.max_rwa_share_bps, 4_000);

    let rwa_market = MarketId::new("RWA/tQUOTE");
    let order = OrderIntent {
        market: rwa_market.clone(),
        kind: InstrumentKind::RwaLinked,
        side: Side::Buy,
        size_micro: 25 * MICRO,
        limit_price_micro: 1 * MICRO,
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
                mark_price_micro: Stamped::new(1 * MICRO, 0),
            },
            Position {
                market: MarketId::new("R2"),
                kind: InstrumentKind::Spot,
                net_size_micro: -50 * MICRO,
                mark_price_micro: Stamped::new(1 * MICRO, 0),
            },
        ],
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    };
    assert_eq!(clean.gross_exposure_micro(), 100 * MICRO);
    let v = e.evaluate(&order, &clean, &ctx);
    assert!(v.is_ok(), "20% RWA share against a 40% cap must be approved, got {v:?}");

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
                mark_price_micro: Stamped::new(1 * MICRO, 0),
            },
            Position {
                market: MarketId::new("R2"),
                kind: InstrumentKind::Spot,
                net_size_micro: -20 * MICRO,
                mark_price_micro: Stamped::new(1 * MICRO, 0),
            },
            Position {
                market: rwa_market.clone(),
                kind: InstrumentKind::RwaLinked,
                net_size_micro: 20 * MICRO,
                mark_price_micro: Stamped::new(1 * MICRO, 0),
            },
        ],
        free_margin_micro: 1_000 * MICRO,
        realized_pnl_today_micro: 0,
        consecutive_losses: 0,
    };
    assert_eq!(loaded.gross_exposure_micro(), 60 * MICRO);
    assert_eq!(loaded.exposure_of_kind_micro(InstrumentKind::RwaLinked), 20 * MICRO);

    match e.evaluate(&order, &loaded, &ctx) {
        Err(Refusal::RwaShareTooLarge { got_bps, limit_bps }) => {
            assert_eq!(limit_bps, 4_000);
            // 45 of 85 projected gross is 5294 bps. Pinning the exact value is what kills the
            // mutants on the reporting arithmetic at lib.rs:505: any of `*` -> `+`, `/` -> `*`
            // or `/` -> `%` moves this number.
            assert_eq!(got_bps, 5_294, "the reported share must be the real fraction");
        }
        other => panic!("expected RwaShareTooLarge, got {other:?}"),
    }
}'''


def replace_fn(src, name, new_body):
    """Replace a whole `#[test] fn name() { ... }` item, brace-matched."""
    idx = src.find(f"fn {name}()")
    if idx < 0:
        raise SystemExit(f"function {name} not found")
    # Walk back to the start of its attribute block.
    start = src.rfind("#[test]", 0, idx)
    if start < 0:
        raise SystemExit(f"no #[test] above {name}")
    # Brace-match forward from the opening brace of the fn body.
    open_brace = src.index("{", idx)
    depth = 0
    i = open_brace
    while i < len(src):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    return src[:start] + new_body + src[i + 1:]


def main():
    src = open(PATH, encoding="utf-8").read()
    if "the first version of this test fail against the per-market cap" in src:
        print("  fixtures already fixed")
        return 0
    for name, body in [
        ("the_gross_projection_adds_to_current_gross_and_its_boundary_is_inclusive", GROSS_NEW),
        ("the_net_skew_projection_is_signed_and_its_boundary_is_inclusive", NET_NEW),
        ("the_rwa_share_cap_is_a_real_fraction_of_projected_gross", RWA_NEW),
    ]:
        src = replace_fn(src, name, body)
        print(f"  rewrote {name}")

    # The `book_with_exposure` helper is still used by the market-projection and mark-age tests,
    # both of which pass, so it stays.
    open(PATH, "w", encoding="utf-8", newline="\n").write(src)
    print("  three fixtures rebuilt to satisfy the checks that run BEFORE the one under test")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
