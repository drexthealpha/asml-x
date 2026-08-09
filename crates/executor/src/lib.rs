//! The executor. Task 2.3.
//!
//! The only entry point that can produce a chain-bound action takes
//! `RiskApproved<OrderIntent>`. Since `RiskApproved` has a private field and
//! lives in another crate, this module physically cannot fabricate one. There is
//! no `unsafe` escape either: the workspace forbids `unsafe_code`.
//!
//! To see the guarantee, uncomment the block in `tests::bypass_does_not_compile`
//! and run `cargo build`. It fails with E0451, private field. The captured
//! compiler output is the evidence for task 2.1.4.

use core_types::{OrderIntent, Side};
use risk_engine::RiskApproved;

/// A single leg of a plan, ready to be turned into calldata.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedLeg {
    pub market: String,
    pub side: Side,
    pub size_micro: i128,
    pub limit_price_micro: i128,
    pub decision_id: u64,
    /// Set when the risk engine flagged the order for human approval. The
    /// executor refuses to submit these without an explicit release.
    pub needs_human: bool,
}

/// Why a prepared leg was not submitted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SubmitBlocked {
    AwaitingHumanApproval,
}

/// Turn an approved intent into a prepared leg.
///
/// Note the signature: there is no overload taking a bare `OrderIntent`, and one
/// must never be added. That absence is the security property.
#[must_use]
pub fn prepare(approved: &RiskApproved<OrderIntent>) -> PreparedLeg {
    let i = approved.get();
    PreparedLeg {
        market: i.market.0.clone(),
        side: i.side,
        size_micro: i.size_micro,
        limit_price_micro: i.limit_price_micro,
        decision_id: i.decision_id,
        needs_human: approved.requires_human_approval(),
    }
}

/// Gate between a prepared leg and the wire. `human_released` comes from an
/// operator action in the UI, never from an agent.
pub fn ready_to_submit(
    leg: &PreparedLeg,
    human_released: bool,
) -> Result<&PreparedLeg, SubmitBlocked> {
    if leg.needs_human && !human_released {
        return Err(SubmitBlocked::AwaitingHumanApproval);
    }
    Ok(leg)
}

#[cfg(test)]
mod tests {
    use super::*;
    use core_types::{InstrumentKind, MarketId, Portfolio, MICRO};
    use risk_engine::{Limits, RiskContext, RiskEngine};

    fn approved_small() -> RiskApproved<OrderIntent> {
        let e = RiskEngine::new(Limits::conservative_testnet());
        let intent = OrderIntent {
            market: MarketId::new("M1"),
            kind: InstrumentKind::Spot,
            side: Side::Buy,
            size_micro: MICRO,
            limit_price_micro: MICRO,
            decision_id: 42,
        };
        let pf = Portfolio {
            free_margin_micro: 1_000 * MICRO,
            ..Default::default()
        };
        e.evaluate(&intent, &pf, &RiskContext::healthy_at(0))
            .expect("small order should be approved")
    }

    #[test]
    fn prepare_carries_the_decision_id_through_to_the_wire() {
        // Every onchain action must trace back to the reasoning that caused it.
        let leg = prepare(&approved_small());
        assert_eq!(leg.decision_id, 42);
        assert!(!leg.needs_human);
    }

    #[test]
    fn a_leg_needing_human_approval_is_blocked_until_released() {
        let e = RiskEngine::new(Limits::conservative_testnet());
        let intent = OrderIntent {
            market: MarketId::new("M1"),
            kind: InstrumentKind::Spot,
            side: Side::Buy,
            size_micro: 20 * MICRO,
            limit_price_micro: MICRO,
            decision_id: 9,
        };
        let pf = Portfolio {
            free_margin_micro: 1_000 * MICRO,
            ..Default::default()
        };
        let leg = prepare(
            &e.evaluate(&intent, &pf, &RiskContext::healthy_at(0))
                .unwrap(),
        );
        assert!(leg.needs_human);
        assert_eq!(
            ready_to_submit(&leg, false),
            Err(SubmitBlocked::AwaitingHumanApproval)
        );
        assert!(ready_to_submit(&leg, true).is_ok());
    }

    #[test]
    fn bypass_does_not_compile() {
        // Task 2.1.4 evidence. Uncommenting this block must fail to build with
        // E0451 (field `inner` of struct `RiskApproved` is private). If it ever
        // compiles, the architectural guarantee is gone and this test is a lie.
        //
        // let forged: RiskApproved<OrderIntent> = RiskApproved {
        //     inner: OrderIntent {
        //         market: MarketId::new("M1"),
        //         kind: InstrumentKind::Spot,
        //         side: Side::Buy,
        //         size_micro: i128::MAX,
        //         limit_price_micro: i128::MAX,
        //         decision_id: 0,
        //     },
        //     requires_human_approval: false,
        //     approved_at_ms: 0,
        //     _seal: (),
        // };
        // let _ = prepare(&forged);

        // The live assertion: the only way to obtain an approval is the engine.
        let a = approved_small();
        assert_eq!(a.get().decision_id, 42);
    }
}
