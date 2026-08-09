# ADR-009: a labelled RWA stand-in, not a mock pretending to be real

Date 9 Aug 2026. Status ACCEPTED. Task 0.4.5, Phase 5.

## Context
Task 0.4 established that no RWA-linked instrument is live on X Layer testnet. The
plan's decision gate said: do not plan strategies against instruments that do not
exist, and if none exist, either use an outcome market as a proxy or deploy our own
minimal instrument labelled as a stand-in.

## Decision
Deploy `RwaVault`, a minimal instrument that models the four RWA properties that
actually change agent behaviour, and label it `SELF-DEPLOYED STAND-IN` everywhere it
appears.

What it models and why each one earns its place:
- Oracle mark with a last-update timestamp. RWA marks are attestations, not traded
  prices, so age is a first-class risk rather than a detail.
- Redemption window schedule. Primary redemption is periodic, so exposure taken just
  before a window closes is locked for a cycle.
- Issuer pause flag. A real issuer can halt the instrument, and an agent that ignores
  that can be long something it cannot exit.
- Monotonic yield index. The instrument earns while held, which changes the
  arithmetic of holding versus flattening.

What it deliberately does NOT model, stated rather than implied: credit events, NAV
haircuts, legal wrapper, KYC gating on transfer, secondary-market fee schedules.

## Why this is not the fake win the plan warned about
The named risk was "RWA intelligence that is a cosmetic label on the same generic
logic", and "a mock the judge assumes is real". Both are addressed structurally:

1. The refusals are real and enforced onchain by `RwaRiskGuard`, proven by seven
   Halmos theorems, 18 of 18 mutations RED, and live triggers on chain 1952 with
   transaction hashes.
2. The side-by-side evidence shows the SAME order approved on the crypto market and
   refused on the RWA market, with the refusal naming an RWA-specific cause, plus a
   healthy case where both approve. That healthy case is the important half: it
   proves the layer is instrument-specific rather than a global brake.
3. Provenance is labelled in the contract header, in deployments.md, and in the gate
   report. It is never described as a live third-party protocol.

## Cost, stated plainly
The instrument is ours, so its behaviour is bounded by what we wrote, and the yield
and redemption mechanics are simplifications. Nothing here demonstrates handling a
real issuer's actual redemption queue. The claim is that the RISK LAYER is real and
enforced, not that the instrument is.

## Migration
The four reads the agent depends on are `riskView()` on the vault and
`divergenceBps()` on the guard. Any real RWA protocol exposing an oracle mark with a
timestamp, a pause flag, and a redemption schedule can be adapted behind the same
two calls without touching the risk engine or the decision engine.
