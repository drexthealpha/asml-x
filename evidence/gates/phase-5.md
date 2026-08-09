# Phase 5 gate: the AI-RWA layer is live and enforced

Captured 9 Aug 2026. Chain 1952. This is the phase that gates the AI-RWA track.

## Deployed

| contract | address |
|---|---|
| RwaVault (SELF-DEPLOYED STAND-IN) | `0x3BF12df3BB0b6f0dF8c57089ab78e402bf698F84` |
| RwaRiskGuard | `0x401Ef3E4b9b838A021109c3BBebb7FDC70Cb9278` |

RWA market id `0xb87ddfac6c6e92e03338f4740cb958f7966abe0a7c132510824697e5994bacba`.
Provenance labelled per ADR-009. Never presented as a live third-party protocol.

## Four RWA-specific refusals, proven three ways each

| refusal | unit tests | Halmos | LIVE on chain |
|---|---|---|---|
| issuer paused | yes | `check_pausedRefusesEveryAmount` | REFUSED(IssuerPaused) |
| oracle stale | yes | concrete only, see note | REFUSED(OracleStale) |
| redemption window too close | yes | concrete only, see note | REFUSED(RedemptionWindowTooClose) |
| oracle versus market divergence | yes | `check_divergenceBoundaryIsExact` | REFUSED(OracleMarketDivergence) |

Note on the two time-dependent properties: they are proven by concrete tests with
`vm.warp` and by live triggers, not symbolically. The symbolic suite is deliberately
time-free to avoid depending on cheatcode behaviour that varies between prover
versions. Stated rather than glossed.

Live evidence: `evidence/rwa-live/live-triggers.txt`. Every step records the guard's
own view, the attempt, and the outcome, with transaction hashes.

## THE ASYMMETRY: exits are never blocked

Proven at three levels, because this is the property that separates a risk control
from a trap:
- onchain live: with the issuer paused, `addExposure` REFUSED and `reduceExposure`
  ACCEPTED in the same session (`0xd2ae42fd...`)
- symbolically: `check_reduceIsNeverBlockedByRwaConditions`, for all add and cut
  amounts, with pause and enormous divergence both active
- offchain: `exiting_an_rwa_position_is_never_blocked_by_any_rwa_condition`

The offchain half derives "is this order reducing" from the SIGNS of current exposure
and the new order, not from a `reduce_only` flag on the intent. A flag is something an
agent could set wrongly and slip past every RWA refusal. Signs cannot lie.

## Side-by-side, task 5.3.4

Same order, same live signals, crypto market versus RWA market. Run across four
states. `evidence/rwa-live/side-by-side.txt`.

| state | crypto | RWA | divergent | RWA-specific reason |
|---|---|---|---|---|
| healthy | APPROVED | APPROVED | false | n/a |
| issuer paused | APPROVED | REFUSED RwaIssuerPaused | true | true |
| oracle diverged 1200 bps | APPROVED | REFUSED RwaOracleMarketDivergence{1200,300} | true | true |
| restored | APPROVED | APPROVED | false | n/a |

The onchain `rwaTradeableFlag()` agreed with the offchain engine in every case.

The healthy row is the most important one. Without it, the layer could be a global
brake wearing an RWA label. With it, the refusals are demonstrably specific to the
instrument and its state.

## Verification position

- 49 Foundry tests, including 22 RWA tests
- 7 Halmos theorems on the RWA guard, all passing; injected violation caught (removing
  the pause refusal made `check_pausedRefusesEveryAmount` FAIL)
- 18 of 18 RWA mutations RED, zero gaps, both onchain and offchain
- Full Rust workspace green

## Three real defects found by the mutation gate

1. Nothing tested that a non-issuer cannot pause the vault. Removing `onlyIssuer`
   from `setPaused` stayed GREEN. An unguarded pause lets anyone halt the instrument
   or clear a halt the issuer set. Covered now for every issuer-only entry point.
2. Nothing tested that setting a price refreshes its timestamp. Removing the refresh
   stayed GREEN. That mutation would leave a freshly-marked instrument permanently
   untradeable, refusing for a reason that is no longer true.
3. Two mutation patterns silently failed to apply and were reported as inconclusive.
   A mutation that does not apply proves nothing, so both were rewritten as
   single-line patterns.

## A design flaw fixed rather than tuned around

The RWA concentration cap was originally a pure share of gross. On an empty book the
first RWA position is 100 percent of gross, so any share cap below 10000 bps refused
it forever. That is not a conservative limit, it is an unsatisfiable one. The rule is
now: RWA exposure may reach the share of gross OR an absolute floor, whichever is
larger. The cap is also skipped when reducing, for the same reason every other RWA
check is.

## What is NOT claimed

- The instrument is ours. Its yield and redemption mechanics are simplifications, and
  nothing here demonstrates handling a real issuer's redemption queue.
- No RWA strategy PnL. The claim is that the risk layer is real and enforced.
- Yield-aware quote skew and RWA hedging from the plan's 5.3.1 and 5.3.3 are not
  built. The yield index is read and journalled but does not yet enter the scoring
  function. Stated plainly rather than implied by the phase name.
