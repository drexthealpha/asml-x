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

Two more, added because they are the ones a reader is most likely to over-read:

- It is **not** profitable, and that is now MEASURED rather than merely unmeasured. See §5.
- AggLayer settlement is **INFERRED, never verified.** Reading chain 196's deployed bytecode
  found a standard OP Stack bridge stack and no AggLayer path visible from L2 at all. An
  earlier version of the internal notes asserted it; the assertion did not survive being
  checked, and is recorded in
  [docs/verified/onchain-reverse-engineering-196.md](verified/onchain-reverse-engineering-196.md).

The claim is narrower: this is a working prototype of an AI financial operating system with
specialised depth in AI-RWA risk, **running live on X Layer mainnet, chain 196, with real
OKB**, and developed against testnet 1952.

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

## 4. The coordination server's burst stall — FIXED

**Status:** RESOLVED. This entry is kept rather than deleted, because the wrong diagnosis is
the useful part.

v1 observed the server stop responding during a 40-request burst, concluded a half-open
client was parked in `read_line`, and added per-socket read and write timeouts. **That did
not work, and could not have:** a deadline on each socket does not shorten a queue, and the
queue was the problem. The gate report said so at the time rather than pretending otherwise.

Fixed by giving connections their own workers. The rate limiter's 429 path is now
**DEMONSTRATED, not INFERRED** — it trips on request 20, observed:
[evidence/phase6/rate-limit-429.txt](../evidence/phase6/rate-limit-429.txt) and
[evidence/phase6/burst-fixed.md](../evidence/phase6/burst-fixed.md).

---

## 5. Realized PnL exists now, and the agent is not profitable

**Status:** the most important entry to read. It changed, and the direction it changed in is
not flattering.

**Earlier versions of this file said "no realized PnL anywhere". That is no longer true.**
Decisions now settle to a signed figure in money, recorded against the decision that made the
prediction, carrying every input so a reader can recompute it `[C-1403]`.

What the numbers actually say:

- Signal hit rate **40.0% on n = 10**. Below a coin flip.
- Total realized PnL across 8 settlements: 3 profitable, 4 losing, 1 flat.
- Decision 176 predicted down, the mid moved against it, and it settled to **−37,500 micro
  quote**.

**Nothing here supports any claim that this trades profitably, and the failure to is now
measured rather than merely unmeasured.** That is a stronger form of the same disclosure.

Two things the figure is not:

1. **Not cash.** It is mark-to-market against a later observed mid, not proceeds from a
   closing trade. Every settlement row states this in its own `basis` field.
2. **Not an exogenous forecast.** The seeded book is static, so nothing settles on its own.
   The mid moves because a script posts real orders to move it, and the evidence says so
   *above* the numbers rather than below them `[C-1405]`.

The baseline comparison is still kept in its unflattering form. Scoped correctly to a
pre-declared window the engine chose one distinct action, the same count as the naive
baseline, because a static book plus deterministic scoring must produce a repeated decision.
An earlier version compared every journal entry ever written and inflated the engine's
variety to 5 against 1. The corrected, worse-looking number is what ships:
[evidence/gates/phase-4.md](../evidence/gates/phase-4.md).

---

## 6. Learning is proven as a mechanism, not as an improvement

**Status:** deliberate, sample sizes disclosed and attached to every figure on screen.

What is proven: outcomes settle against a genuinely later price, state persists across
restarts, parameters respond to measured accuracy, every change records its trigger and its
sample size, and a learned parameter demonstrably changes the chosen action.

**What the mechanism did here:** the learner noticed its signal was not paying and cut
`momentum_weight_bps` from its default of 2000 to **391**, while raising
`thin_book_penalty_bps` from 150 to **1225**, until the agent stopped taking positions and
chose `hold` `[C-1406]`.

That is the loop working. It is not evidence that the agent trades better afterwards, and
n = 10 cannot be.

**A defect found and fixed while building this:** the learner wrote its parameter history on
save and silently dropped it on load, so the displayed history was only ever the current
process's changes and understated the effect by two orders of magnitude `[C-1407]`.

**The counterparty flow is simulated and labelled.** Chain 1952 has no organic flow, so the
scripts cancel the live book and post new levels to drive a price path. The orders, cancels,
fills and prices are real onchain state. What is synthetic is the existence of a counterparty
at all, so the hit rate says nothing about a real market.

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
| UI does not auto-refresh | It reads files at load. Reload to update. There IS a "Run full demo" button now, which runs a real cycle and refuses to report success if the journal did not grow `[C-905]`. |
| Guard tracks absolute exposure, not signed size | So direction is not recoverable from the guard alone. The runtime labels the portfolio reconstruction as an approximation and attributes direction from the journal. |
| Two time-dependent RWA properties are not proven symbolically | The symbolic suite is deliberately time-free to avoid depending on cheatcode behaviour that varies between prover versions. Both are covered by concrete tests with `vm.warp` and by live triggers. |
| Halmos cannot execute MCOPY | Which Solidity emits when returning a `string`. A string-free view exists for the prover, with a fuzz test pinning the two views together so they cannot diverge. |
| ~~No mainnet deployment~~ | **NO LONGER TRUE, and the entry is kept so the change is visible.** This is deployed and running on X Layer **mainnet, chain 196, with real OKB**: agent loop, refusal, fee event, user deposit and withdrawal, re-verified from chain rather than from any file here `[C-1602]`. ADR-003 was superseded. |
| 9 clippy `identity_op` warnings in risk-engine tests | Cosmetic, in test code, not cleaned. |
| 60-minute unattended run never performed (plan 2.4.6) | The longest continuous observed run is a few minutes. Stability beyond that is untested. |
| gemini-grounding is unavailable on QUOTA, not capability | Corrected from an earlier claim that it was unreachable. The key authenticates and the DoH-pinned transport reaches the host; every model returns HTTP 429. No Gemini answer is quoted as grounded anywhere in this repo. codebase-memory-mcp and paperscraper WERE installed and used; see [evidence/TOOL-USAGE.md](../evidence/TOOL-USAGE.md). |
| The decision trace exports to stdout, not to an OTLP collector | Real OpenTelemetry SDK, real SDK-assigned span tree, no infrastructure to stand up. Swapping in `opentelemetry-otlp` is a few lines and is not done only because there is no collector to point it at `[C-1402]`. |

---

## 8. Process honesty

Fourteen times during this build an artifact looked green while proving nothing: vacuous
property tests, mutation patterns that silently failed to apply, a formal verification
pipeline that verified zero tests for two runs, an 18-versus-6 decimal mismatch that made a
broken agent look merely cautious, backwards taker economics that made it hold forever and
look prudent, a comparison scoped to every entry ever written, an unsatisfiable RWA
concentration cap, a flat market that scored every forecast as wrong, forecasts discarded on
process exit, and a crossed book that paid the agent to trade.

Later phases added more of the same shape, and they are listed because the pattern is the
point:

- A mutation gate **restored a file with `mv` and did not rebuild**, because the backup
  carried an older mtime than the mutated artifact, so it reported the MUTATED results as the
  restored ones.
- An invariant gate **caught its mutation by replaying a cached counterexample** from
  Foundry's `cache/invariant/failures/`, which proves only that a counterexample once existed
  on disk. The cache is now cleared before every run.
- The journal's `outcome` field **carried a different decision's result**: row 163 held
  decision 87's outcome, so anyone reading a row was reading another decision's number.
- The learner **wrote parameter history on save and dropped it on load**, understating the
  learning effect by two orders of magnitude while looking entirely plausible.
- A mainnet checker **expected every transaction to succeed** and flagged the one that proves
  the risk gate refuses an over-cap trade — inverting the meaning of the most important
  negative result in the project.
- **A source file was destroyed by a write that did not read it first.** It was untracked, so
  no copy existed in git or in any transcript, and it had to be REBUILT rather than
  recovered. The rebuild is declared in the file's own header.

Two ADRs were **rewritten against their own author** when the measurements came back wrong:
ADR-018, where a mobile-layout emergency turned out to be my own measurement code ignoring
scroll clipping, and ADR-019, where "crates.io is unreachable from this machine" was asserted
without ever being tested and was simply false.

Every one was caught by deliberately breaking the thing, scoping it honestly, or looking at
real output on a screen. None was caught by reading passing tests. That is why every gate in
this repository is mutation-tested, and why the failure modes are shipped as checkable
artifacts rather than described.
