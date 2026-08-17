"""Kill the last real surviving mutant: lib.rs:502 `>` -> `>=` on the RWA share allowance.

After the first round of 11 tests, 35 of 37 survivors were dead. The two left were:

  502:30  replace > with >= in RiskEngine::evaluate   <- a real gap, killed by the test below
  504:52  replace > with >= in RiskEngine::evaluate   <- an EQUIVALENT mutant

504 was `if projected_gross > 0`, and `>= 0` behaves identically because projected_gross is
`gross + order_notional` where gross is non-negative and a zero-or-negative order size is refused
earlier. The else branch was unreachable, so the fix was to delete the dead branch rather than to
write a test for code that cannot run. That is in lib.rs with the reasoning in a comment.

502 is different: it is a genuine untested boundary. `projected_rwa > allowance` refuses, so
projected_rwa EQUAL to the allowance must be ALLOWED. Nothing pinned that.

The fixture has to hit exact equality, which needs arithmetic rather than trial and error.
Let G be non-RWA gross, R existing RWA exposure, X the new RWA order:
    projected_rwa   = R + X
    projected_gross = G + R + X
    allowance       = 40% of projected_gross   (max_rwa_share_bps = 4000)
Equality means R + X = 0.4 * (G + R + X), i.e. 2.5(R + X) = G + R + X, i.e. G = 1.5(R + X).
Choose R = 10, X = 10, so R + X = 20 and G = 30.
Then projected_gross = 50, allowance = max(40% of 50, absolute 10) = max(20, 10) = 20, and
projected_rwa = 20. Equal, so it must be approved.
Every earlier check also passes at these numbers: the RWA market projects to 20 (cap 50), net to
20 (cap 75), gross to 50 (cap 200), and the order notional is 10 (cap 25). Two opposing non-RWA
legs of 15 keep net skew clear.
"""
import io

PATH = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/crates/risk-engine/src/tests.rs"
MARKER = "the_rwa_allowance_boundary_is_inclusive"

TEST = r'''

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
'''


def main():
    src = open(PATH, encoding="utf-8").read()
    if MARKER in src:
        print("  already present")
        return 0
    with io.open(PATH, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(TEST)
    print("  appended the RWA allowance boundary test")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
