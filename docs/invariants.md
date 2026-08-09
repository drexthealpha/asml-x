# Invariants

Every property this project relies on, with its verification status. A property proven for
all inputs in a stated range is `DEMONSTRATED` with a link to the prover report. A property
that is only tested by example, or assumed from structure, is `INFERRED` and says so.

The distinction matters: an example-based test says the code matches one belief on one input.
A symbolic proof says no counterexample exists in the range.

Tooling: [Halmos](https://github.com/a16z/halmos), see
[decisions/ADR-007-formal-verification-tool.md](decisions/ADR-007-formal-verification-tool.md)
for why not Certora. Reports in [../evidence/formal/](../evidence/formal/).

---

## Proven symbolically: base risk guard

Suite `contracts/test/RiskGuardSymbolic.t.sol`, 7 theorems, all passing.
Report: `evidence/formal/halmos-risk-guard.txt`.

| # | property | function | status |
|---|---|---|---|
| 1 | No sequence of adds can push per-market exposure above its cap | `check_capIsNeverExceeded` | `DEMONSTRATED` |
| 2 | No sequence of adds can push gross exposure above the global cap | `check_grossIsNeverExceeded` | `DEMONSTRATED` |
| 3 | Gross exposure always equals the sum of its per-market parts | `check_grossEqualsSumOfParts` | `DEMONSTRATED` |
| 4 | Once killed, `addExposure` reverts for every amount | `check_killedRefusesEveryAmount` | `DEMONSTRATED` |
| 5 | The agent role can never clear the kill switch, for any caller | `check_onlyOwnerCanRevive` | `DEMONSTRATED` |
| 6 | Reducing exposure never underflows and never exceeds the held amount | `check_reduceNeverUnderflows` | `DEMONSTRATED` |
| 7 | Only the owner can raise a market cap, for any caller | `check_onlyOwnerCanSetCaps` | `DEMONSTRATED` |

**Proof mutation:** injecting a one-wei cap violation causes theorems 1 and 2 to FAIL.
`scripts/16-proof-mutation.sh`. A prover run that cannot fail proves nothing, so this is run
as a gate rather than assumed.

---

## Proven symbolically: RWA risk guard

Suite `contracts/test/RwaSymbolic.t.sol`, 7 theorems, all passing.
Report: `evidence/formal/halmos-rwa-guard.txt`.

| # | property | function | status |
|---|---|---|---|
| 8 | A paused issuer refuses new exposure for every amount | `check_pausedRefusesEveryAmount` | `DEMONSTRATED` |
| 9 | **De-risking is never blocked by any RWA condition, for any add and cut** | `check_reduceIsNeverBlockedByRwaConditions` | `DEMONSTRATED` |
| 10 | The oracle-versus-market divergence boundary is exact | `check_divergenceBoundaryIsExact` | `DEMONSTRATED` |
| 11 | Inherited cap arithmetic survives the subclass override | `check_inheritedCapsSurviveTheOverride` | `DEMONSTRATED` |
| 12 | The kill switch still stops the RWA path for every amount | `check_killedRefusesEveryAmountOnTheRwaPath` | `DEMONSTRATED` |
| 13 | No caller but the owner can loosen the RWA policy | `check_onlyOwnerCanLoosenTheRwaPolicy` | `DEMONSTRATED` |
| 14 | The yield index can never decrease, for any pair of values | `check_yieldIndexIsMonotonic` | `DEMONSTRATED` |

**Property 9 is the most important invariant in the project.** A stale oracle or a paused
issuer is exactly when an agent most needs to exit. A guard that blocks the exit converts a
risk control into the risk itself. It is proven symbolically for all amounts with pause and
enormous divergence both active, unit-tested, and demonstrated live onchain (tx
`0xd2ae42fd`, in `evidence/rwa-live/live-triggers.txt`).

**Proof mutation:** removing the issuer-pause refusal causes theorem 8 to FAIL.
`scripts/21-rwa-formal.sh`.

---

## Proven by exhaustive property testing, not symbolically

`proptest` over the pure Rust risk engine. These are randomised over large input spaces
rather than proven, so they are `INFERRED` with a strong basis, not `DEMONSTRATED`.

| property | basis |
|---|---|
| An approved order always re-validates against the risk engine | `approved_actions_always_satisfy_the_risk_engine`, proptest |
| Candidate ranking is deterministic for identical inputs | `ranking_is_deterministic`, proptest |
| Every limit function refuses at its boundary | proptest per limit, 14/14 mutation RED |

---

## Enforced by the type system, which is stronger than any test

| property | mechanism | status |
|---|---|---|
| The agent cannot submit an order that did not pass the risk gate | Signing requires `RiskApproved<OrderIntent>`, whose only constructor is inside the risk engine. Forging one fails to COMPILE. | `DEMONSTRATED`, [../evidence/bypass-compile-error.txt](../evidence/bypass-compile-error.txt) |
| Learning cannot widen a risk limit | `Learner` has no field, argument, or return type mentioning `Limits`. It emits scoring parameters only. | `DEMONSTRATED` by construction plus `learning_cannot_reach_a_risk_limit_because_it_has_no_type_for_one` |
| The risk engine cannot read a clock | Time is a function argument. No `SystemTime` or `Instant` in the crate. | `DEMONSTRATED`, [decisions/ADR-005-no-floats-no-clocks.md](decisions/ADR-005-no-floats-no-clocks.md) |
| The risk engine cannot use floating point | `float_arithmetic` denied at the workspace lint level | `DEMONSTRATED` |

---

## Verified live onchain, not just in a prover

A proof says the code matches the specification. A live transaction says the deployed
bytecode on a real chain agreed.

| property | evidence |
|---|---|
| A multi-leg batch is atomic: guard leg first, so a breach reverts everything | `evidence/spine-run-01/README.md` |
| A market cap refusal actually stops a real submission | same |
| The kill switch actually halts a running agent | same |
| De-risking works while killed | same |
| All four RWA refusals fire on real state | `evidence/rwa-live/live-triggers.txt` |
| `gross() == sumOfParts()` holds after real agent activity | `evidence/gates/phase-4.md`, 4.0e18 to 10.075e18 |

---

## Stated but NOT proven

Listed so nothing here is mistaken for verified.

| property | why not proven |
|---|---|
| Two time-dependent RWA refusals (stale oracle, window proximity) | The symbolic suite is deliberately time-free, to avoid depending on cheatcode behaviour that varies between prover versions. Covered by concrete `vm.warp` tests and by live triggers. |
| `rwaTradeable` and `rwaTradeableFlag` never disagree | Halmos cannot execute MCOPY, which Solidity emits when returning a `string`, so the string-returning view cannot enter a proof. Pinned by a fuzz test across paused, stale, divergent and window states. |
| The venue's matching logic is correct under concurrency | Single-writer in practice on this testnet. Not proven, and a real venue replaces this contract entirely. |
| The offchain risk engine and the onchain guard always agree | They implement the same refusals deliberately, and the side-by-side run showed agreement in every observed case, but no proof relates the two implementations. This is the most valuable unproven property in the project. |
| Learning converges | Bounded on both sides by clamps, and a coinflip signal is shown to lose weight, but no convergence proof exists. |

---

## How to re-run every gate

```bash
cargo test --workspace                    # 19 suites
bash scripts/10-contracts-test.sh         # 50 Foundry tests, 4 invariant campaigns
bash scripts/16-proof-mutation.sh         # 7 base theorems + injected violation
bash scripts/21-rwa-formal.sh             # 7 RWA theorems + injected violation
bash scripts/08-mutation-gate.sh          # 14/14 risk engine mutations RED
bash scripts/11-contract-mutation.sh      # 15/15 contract mutations RED
bash scripts/25-rwa-mutation.sh           # 18/18 RWA mutations RED
bash scripts/32-learning-mutation.sh      # 12/12 learning mutations RED
bash scripts/36-docs-audit.sh             # checks these numbers against reality
```

The last one exists because a document claiming 49 tests when there are 50 is an unbacked
claim. It caught exactly that on its first run.
