# Phase 1 gate: toolchain provisioning

**CLOCK STOPS HERE per TASKS.md:** v1 product plus a fully provisioned toolchain and an honest tool
ledger. No new product capability. This phase buys optionality, not score.

It bought one thing that does count, and it was not on the plan: **cargo-mutants found 37 surviving
mutants in the risk engine**, the crate holding every limit check. That is a real defect class in the
test suite, found by installing a tool rather than by reasoning about the tests.

## Every subtask, and what it produced

| task | tool | outcome |
|---|---|---|
| 1.1 | toolchain floor | PASS. The gate itself was fixed after printing a FALSE GREEN: `{ ... } | tee` runs in a subshell, so `FAIL` increments were discarded and it printed "failures: 0" directly under three failures. Python floor corrected 3.11 to 3.10. |
| 1.2 | halmos 0.3.3 | PASS. Installed via `uv tool install --python 3.12`. Replaced a stale **0.1.13** that the VERIFIED FACTS table already claimed was 0.3.3. Both versions prove all 7 RWA theorems and catch the injected violation. |
| 1.3 | kontrol | SUBSTITUTED. Four R-SEARCH-2 rungs named. Capability covered twice over by halmos and hevm. |
| 1.4 | hevm 0.57.0 | PASS. 5 independent `prove_` theorems. Two facts learned the hard way: hevm lives at **argotorg/hevm**, not ethereum/hevm, and discovery needs the std-test base contract even when no cheatcode is called. |
| 1.5 | scribble | PASS, and the PASS is a differential: the plain contract accepts 150, the instrumented one reverts. An instrumented contract that never reverts proves nothing. |
| 1.6 | act | SUBSTITUTED. Nix-only build, **no release binary at all**, and act's strongest EVM backend IS hevm, which is already driven directly. Capability lost (a spec language independent of Solidity, Rocq extraction) is stated rather than minimised. |
| 1.7 | cargo-mutants 27.1.0 | PASS, and the phase's real finding. See below. |
| 1.8 | gitleaks 8.30.1 | PASS. Full history. |
| 1.9 | codebase-memory-mcp 0.9.0 | PASS. 5051 nodes, 12913 edges. Returns `RiskApproved` at `crates/risk-engine/src/lib.rs:251`; an invented symbol returns `total:0`, so the hits are signal. **R-SEARCH-4 is enforceable for the first time.** |
| 1.10 | paperscraper | PASS. 15 real arxiv records, 4 cited decisions. The first version of the script printed a PASS while the query had returned ZERO records; the verdict is now gated on the count. |
| 1.11 | gemini-grounding | SUBSTITUTED, and the v1 record CORRECTED. It fails on **quota (HTTP 429)**, not on network and not on the key: the API returns a full model list and authenticated 404s. ADR-004 amended. |
| 1.12 | alloy 2.3.0 | PASS. Identical bytes to the hand-rolled client for the same call at the same pinned block. The CLAUDE.md pin of 1.7.3 was stale. |
| 1.13 | revm 42.0.1 | PASS. Three-way agreement on the cap-breach revert selector, with attempted and cap decoded from the payload. |
| 1.14 | river 0.25.0 | PASS. 0.8608 against a 0.8354 baseline on 79 rows. ADR-011: benchmark only, not a sidecar. |
| 1.15 | frontend stack | PASS. Production build with all 16 versions verified against their pins by a script that exits non-zero on any mismatch. |
| 1.16 | just, DuckDB | PASS on real data. insta DEFERRED to 8.6 and OpenTelemetry to 6.8, both with reasons. |
| 1.17 | agent framework | DECIDED. ADR-012: none on the decision path, because there is no LLM call between snapshot and signature for one to orchestrate. Falsification test is mechanical and currently empty. |
| 1.18 | ledger reconciliation | PASS. **Zero of 47 rows remain PENDING**, and the status vocabulary was widened because three values could not describe the real outcomes without lying by omission. |
| 1.19 | reproducibility audit | Evidence files deleted and regenerated from their commands. `evidence/phase0/reproducibility-audit.md`. |

## The finding: a green mutation table and 37 holes

The four hand-written mutation gates report 14/14, 15/15, 18/18 and 12/12 RED. All true. Then
cargo-mutants generated 107 viable mutants of `risk-engine` and **37 survived the full suite**:

- **No limit boundary was pinned anywhere.** `>` could become `>=` on the mark-age check, the market
  cap, the gross cap, the net skew cap, the free-margin floor, the RWA share cap and the
  human-approval threshold, and every test still passed.
- **The post-trade projection was never exercised against a non-empty book.** `existing + order`
  could become `existing - order` unnoticed, which is exactly the creep-past-a-limit-one-order-at-a-time
  bug the code comment at `lib.rs:448` says the projection exists to prevent. The code was right and
  untested, because almost every test ran against an empty book.
- **The shipped defaults were asserted nowhere.** Every test built its own limits, so
  `Limits::conservative_testnet` (the configuration the demo actually runs) could have `5 * MICRO`
  become `5 + MICRO` with no failure.
- **`is_halted` had no test at all.** Both `-> true` and `-> false` survived, which is the signature
  of an untested public function on the safety surface.

Twelve tests were written, each naming the mutant it kills. Result: **91 caught, 0 survived.**

One of the two final survivors was an EQUIVALENT mutant: `projected_gross > 0` where the else branch
was unreachable, because gross is non-negative and a zero-size order is already refused. The fix was
to delete the dead branch, not to write a test for code that cannot execute.

The general lesson, which is the transferable part: a hand-written mutation gate tests the breaks its
author thought of.

## What this phase did NOT buy

No product capability, as planned. Two tools are installed and unused on purpose
(`lightweight-charts`, `framer-motion`), and four spec-listed UI references were deliberately not
read, with the reason recorded rather than implied. One primary reference read to 70 citations beat
three read to none.

## Reproduce the phase

```bash
bash scripts/45-toolchain-floor.sh        # floor, with the false-green fixed
bash scripts/59-cargo-mutants.sh          # the finding, ~45 min
bash scripts/66-remutate.sh               # the close-out, 91 caught 0 missed
bash scripts/82-repro-audit.sh            # delete every evidence file and regenerate it
grep -cE '^\| [^|]+ \| PENDING' evidence/TOOL-USAGE.md   # 0
```
