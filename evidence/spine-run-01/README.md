# Spine run 01: live on X Layer testnet, chain 1952

Captured 2026-08-09 07:42:35 UTC. Status: DEMONSTRATED.
Every claim below is a real transaction or a real revert on chain 1952.
No mocks, no local fork. Contracts: docs/verified/deployments.md

## A. Multi-leg atomic batch landed

Three legs in one transaction: RiskGuard.addExposure, tQUOTE.approve,
OrderBookVenue.take.

- batch tx: `0x6b4168b0a7ab67fad759ee5d2e337b396675c57410f4b9bd4a11ffa6817a333d`
- explorer: https://www.oklink.com/x-layer-testnet/tx/0x6b4168b0a7ab67fad759ee5d2e337b396675c57410f4b9bd4a11ffa6817a333d
- guard exposure: 0 -> 8000000000000000000
- executor tBASE balance: 0 -> 4000000000000000000
- order remaining base: 10000000000000000000 -> 6000000000000000000

The first leg is required by the contract to be the RiskGuard. A batch that does
not consult the guard first reverts with FirstLegMustBeRiskGuard.

## B. Cap breach refused live, nothing moved

Requested 600e18 exposure against a 500e18 per-market cap.

- transaction refused, exit code 1
- guard exposure unchanged: 8000000000000000000 -> 8000000000000000000
- order remaining unchanged: 6000000000000000000 -> 6000000000000000000

This is the atomicity property doing real work. The take leg never executed, so
no tokens moved at all rather than partially moving and needing an unwind.

## C. Kill switch fired live and stopped the agent

- kill transaction landed, guard.killed became true
- subsequent batch refused, exit code 1
- order remaining unchanged: 6000000000000000000 -> 6000000000000000000

## D. De-risking still works while killed

reduceExposure succeeded while the guard was killed, by design. A kill switch
that traps the agent in its position is worse than the risk it was stopping.
Only the owner can revive, and the agent role cannot, which the unit tests and
the mutation gate both confirm.
