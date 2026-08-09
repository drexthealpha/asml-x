# Limitations

Every known weakness in this project is here. The project rule is that a weakness must be
fixed, cut, or stated as a deliberate reasoned limitation. Nothing is confessed and left
without a reason.

---

## What we do not claim

Verbatim from the specification's own list, and all still true:

- This is **not** the full production ASML system.
- The risk engine is **not** fully institutional grade.
- Self-improvement is **not** unbounded.
- It is **not** ready for large real capital.
- Network effects do **not** yet exist at scale.

The claim is narrower: this is a working prototype of an AI financial operating system with
specialised depth in AI-RWA risk, running live on X Layer testnet, with a documented path to
mainnet.

---

## 1. Exchange OS integration is not demonstrated

**Status:** cut, with evidence, and replaced by a labelled forward commitment.

The specification's core assumed Exchange OS primitives (matching, margining, liquidation,
settlement) were available to build against. They are not, on testnet, as of 9 Aug 2026.

Established by four independent primary probes, recorded in
[verified/exchangeos-availability.md](verified/exchangeos-availability.md):

- The official 23-page Exchange OS whitepaper contains **0** contract addresses, **0**
  occurrences of "testnet", and **1** occurrence of "API".
- The X Layer developer documentation navigation contains **0** references to Exchange OS,
  TradeZone, venue, order book, or outcome market.
- No candidate TradeZone RPC hostname resolves (weak corroboration, the hostnames were
  guesses).
- Press states external-builder venue deployment is scheduled for Q3 2026 via XIP
  governance, and the first venue was run by X Layer itself.

**Why we did not build it anyway:** code claiming to integrate a surface with no testnet
presence would be a mock behind a clean interface. That is the specific failure mode this
project's rules forbid.

**What we did instead:** every Exchange OS reference is tagged `INFERRED` and points at the
availability document. The live demo makes no Exchange OS claim. See
[decisions/ADR-002-exchange-os-claims.md](decisions/ADR-002-exchange-os-claims.md).

**Cost:** the strongest differentiator in the original plan is unavailable, and "integration
with X Layer" rests instead on real deploys, real transactions, OP Stack predeploy use, and
Multicall3.

---

## 2. The venue is self-deployed

**Status:** deliberate, forced by evidence, labelled everywhere.

Chain 1952 carries roughly **110 user transactions across 7 distinct contracts per 300
blocks**, and there is no Uniswap V2 or V3 factory, router, or position manager at any
canonical address. There was nothing liquid to integrate against:
[verified/chain-1952-reality.md](verified/chain-1952-reality.md).

**Cost, stated rather than minimised:** the venue's realism is bounded by what we wrote. A
judge could reasonably read a self-deployed venue as self-dealing. Escrow, transfers and
events are genuinely real so fills cannot be faked, and the guard binds the agent even
against our own venue, but venue-level realism is not demonstrated.

Recorded in [decisions/ADR-001-venue-strategy.md](decisions/ADR-001-venue-strategy.md).

---

## 3. The RWA instrument is a stand-in

**Status:** deliberate, labelled `SELF-DEPLOYED STAND-IN` in the contract header, in
deployments, in the UI, and in every gate report.

`RwaVault` models the four RWA properties that change agent behaviour: an oracle mark with a
timestamp, a redemption window schedule, an issuer pause flag, and a monotonic yield index.

**It does not model:** credit events, NAV haircuts, a legal wrapper, KYC gating on transfer,
or secondary-market fee schedules. Nothing here demonstrates handling a real issuer's actual
redemption queue.

**What is real:** the risk layer. The four refusals are enforced onchain, proven by seven
Halmos theorems, mutation-tested 18 of 18 RED, and demonstrated live with transaction
hashes. The claim is that the risk layer is real and enforced, not that the instrument is.

Recorded in [decisions/ADR-009-rwa-standin.md](decisions/ADR-009-rwa-standin.md).

---

## 4. The coordination server stalls under a rapid burst

**Status:** KNOWN AND NOT FIXED. Remedy identified.

During a 40-request burst the server stops responding and the client times out. The
connection is accepted and never serviced, so the single request-handling thread is stuck
rather than the process being dead. Reproduced twice.

Per-socket read and write timeouts were tried and did **not** resolve it, so that diagnosis
was wrong and the cause remains open.

**Consequences:**
- The rate limiter's 429 path has never been **observed** tripping. It is implemented and
  reachable but marked `INFERRED`, not `DEMONSTRATED`.
- A sustained burst against this endpoint is a denial of service requiring no attacker
  sophistication.

**Remedy, stated but not executed:** give each connection its own thread with `State` behind
a `Mutex`, or replace the hand-rolled accept loop with `tiny_http` 0.12, which handles
connections, transfer and encoding and supports multiple workers on an `Arc<Server>`.
Roughly a thirty line change.

**Why it was not done:** Phase 7 and Phase 8 were unbuilt at the time, and an absent
deliverable costs more than a disclosed limitation. That was a scope call, not an oversight.

12 of 13 other coordination checks pass with real HTTP status codes, including an oversized
request refused by the same risk engine the brain applies to itself.

---

## 5. No realized PnL anywhere

**Status:** deliberate, and the most important limitation to read.

Fills are never marked to a later price for profit accounting. Consequently:

- The engine-versus-baseline comparison measures decision behaviour and risk posture, not
  profitability.
- The learning layer measures directional hit rate, not money.
- **Nothing in this project supports any claim that it trades profitably.**

The baseline comparison is also kept in its unflattering form. Scoped correctly to a
pre-declared window, the engine chose one distinct action, the same count as the naive
baseline, because a static book plus deterministic scoring must produce a repeated decision.
An earlier version of that script compared every journal entry ever written and inflated the
engine's variety to 5 against the baseline's 1. The corrected, worse-looking number is what
ships: [evidence/gates/phase-4.md](../evidence/gates/phase-4.md).

---

## 6. Learning is proven as a mechanism, not as an improvement

**Status:** deliberate, sample sizes disclosed.

What is proven: outcomes settle against a genuinely later price, state persists across
restarts, parameters respond to measured accuracy, every change records its trigger and
sample size, and a learned parameter demonstrably changes the chosen action (12 of 12
mutations RED, including severing the parameter from the decision path).

What is not proven: that the agent trades better afterwards. Sample sizes are single digits.

**The counterparty flow is simulated and labelled.** Because chain 1952 has no organic flow,
`scripts/34-learn-clean-market.sh` cancels the live book and posts a new level to drive a
price path in both directions. The orders, cancels, fills and prices are real onchain state.
What is synthetic is the existence of a counterparty at all, and the price path is chosen by
the simulator, so the hit rate on it says nothing about a real market.

Not built from the plan: retrieval of similar past states (7.2.3). Only two parameters are
learned.

---

## 7. Smaller accepted limitations

| limitation | reason |
|---|---|
| Yield-aware quote skew and RWA hedging not built (plan 5.3.1, 5.3.3) | The yield index is read and journalled but does not enter scoring. Ran out of schedule; disclosed rather than implied by the phase name. |
| No LLM in the loop | The thesis text is generated from signal numbers by ordinary code. An LLM narrating this loop would add words, not intelligence. The bounded interpretation role from the plan was never wired. |
| Sequential order reads, no Multicall3 batching | Multicall3 is deployed at `0xcA11…CA11` on this chain, but batching a dynamic array of calls needs dynamic ABI encoding, which [ADR-008](decisions/ADR-008-chain-client-and-signing.md) deliberately keeps out of the hand-rolled client. Costs milliseconds at current order counts. |
| Signing via `cast` subprocess | Stated plainly rather than wrapped to look native. A hand-rolled secp256k1 signer and RLP encoder is exactly the brittle plumbing this project refuses to hide. Costs tens of milliseconds per submission. |
| Coordination auth is API keys, not wallet signatures | The operator has no browser wallet and a signature scheme adds dependency without adding safety at this scope. Demo keys are hardcoded. See [ADR-010](decisions/ADR-010-coordination-auth.md). |
| UI does not auto-refresh | It reads files at load. Reload to update. No coordination playground and no "run demo" button. |
| Guard tracks absolute exposure, not signed size | So direction is not recoverable from the guard alone. The runtime labels the portfolio reconstruction as an approximation and attributes direction from the journal. |
| Two time-dependent RWA properties are not proven symbolically | The symbolic suite is deliberately time-free to avoid depending on cheatcode behaviour that varies between prover versions. Both are covered by concrete tests with `vm.warp` and by live triggers. |
| Halmos cannot execute MCOPY | Which Solidity emits when returning a `string`. A string-free view exists for the prover, with a fuzz test pinning the two views together so they cannot diverge. |
| No mainnet deployment | Deliberate. See [mainnet-path.md](mainnet-path.md) and [ADR-003](decisions/ADR-003-testnet-only.md). |
| 9 clippy `identity_op` warnings in risk-engine tests | Cosmetic, in test code, not cleaned. |
| 60-minute unattended run never performed (plan 2.4.6) | The longest continuous observed run is a few minutes. Stability beyond that is untested. |
| codebase-memory-mcp and paperscraper never installed | Two of the four mandated tools. Halmos replaced Certora, and gemini-grounding was substituted after its endpoint proved unreachable from this network ([ADR-004](decisions/ADR-004-grounding-substitution.md)). |

---

## 8. Process honesty

Fourteen times during this build an artifact looked green while proving nothing: vacuous
property tests, mutation patterns that silently failed to apply, a formal verification
pipeline that verified zero tests for two runs, an 18-versus-6 decimal mismatch that made a
broken agent look merely cautious, backwards taker economics that made it hold forever and
look prudent, a comparison scoped to every entry ever written, an unsatisfiable RWA
concentration cap, a flat market that scored every forecast as wrong, forecasts discarded on
process exit, and a crossed book that paid the agent to trade.

Every one was caught by deliberately breaking the thing, scoping it honestly, or looking at
real output on a screen. None was caught by reading passing tests. That is why every gate in
this repository is mutation-tested, and why the failure modes are shipped as checkable
artifacts rather than described.
