# ADR-006: what must be onchain

Date 9 Aug 2026. Status ACCEPTED. Task 2.2.1.

## Context
The default answer to "what goes onchain" is nothing, because every contract is
attack surface and audit burden. But ADR-001 makes the venue ours, and a risk
engine that only exists offchain is a claim a judge cannot verify.

## Decision
Four contracts, no more.

1. **MockERC20** (2 instances: test base and test quote). Needed because real
   fills require real token transfers. Labelled a test token everywhere.
2. **RiskGuard**. The binding authority for exposure limits and the kill switch.
   The Rust engine is the pre-check; this contract is the last word. Formally
   verified in Phase 3. Chosen because "risk controls can and do stop the agent"
   is a checklist item, and an onchain guard makes it provable by anyone with an
   explorer rather than trusting our offchain code.
3. **OrderBookVenue**. A minimal escrowed limit order book with maker posts and
   taker fills. Real custody, real transfers, real events. This is the substrate
   the brain trades against.
4. **BatchExecutor**. Atomic multi-leg execution so a quote, take, and hedge
   sequence either fully lands or fully reverts. Chosen because "multi-step
   onchain execution driven by the agent" is a checklist item, and atomicity is
   what makes a mid-sequence failure safe rather than leaving orphan exposure.

## Rejected
- Onchain order matching engine with price-time priority across a full book.
  Too much surface for the deadline, and matching is not what the AI claim rests
  on. The venue matches on explicit taker selection instead.
- Onchain oracle. Phase 5 reads marks from the venue and a stand-in RWA
  instrument, both of which we control, so an oracle adds a component without
  adding provable truth.
- Onchain learning state. Learning belongs offchain; putting it onchain would be
  cost theatre.

## Cost
The venue is ours, so venue realism is bounded by what we wrote. Stated in
ADR-001. Mitigation: escrow, transfers, and events are genuinely real, so fills
cannot be faked, and the guard binds the agent even against our own venue.

## Invariants the guard must hold (Phase 3 CVL targets)
1. No fill can push per-market exposure above its cap.
2. No fill can push gross exposure above the global cap.
3. When killed, every guarded call reverts.
4. Only the owner role can clear the kill switch. The agent role never can.
5. Exposure equals the sum of its per-market parts.
