# Phase 3 gate: formal verification green

Captured 9 Aug 2026. Tool: Halmos, local, no cloud key. ADR-007 records why not
Certora.

## Seven theorems proven for ALL inputs in range, not sampled

| theorem | invariant |
|---|---|
| check_noSequenceOfAddsCanBreakACap | 1, per-market cap over any two adds |
| check_grossCapHoldsAcrossMarkets | 2, gross cap across two markets |
| check_killedBlocksEveryAdd | 3, killed blocks every add for any amount |
| check_onlyOwnerCanRevive | 4, symbolic over the caller address |
| check_onlyOwnerCanRaiseCaps | 4, learning cannot widen a limit, structurally |
| check_grossAlwaysEqualsSumOfParts | 5, across add/add/reduce |
| check_unconfiguredMarketAlwaysFailsClosed | fail-closed for any market id |

Baseline: 7 passed, 0 failed. Output: evidence/formal/halmos-riskguard.txt

## The proofs can fail

Injected violation: per-market cap check loosened by one wei.
Result: 2 proofs FAILED with counterexamples. Restore: 7 passed, 0 failed.
Output: evidence/formal/halmos-injected-violation.txt

## Three defects found while building this gate

Each one made a broken run look like a passing one, which is the precise failure
mode R7 exists to catch. All three are now guarded in the script rather than
remembered.

1. halmos colours its output, so `grep '^\[FAIL\]'` never matched. The first run
   reported "the prover missed a real violation" purely because of ANSI escapes.
2. halmos shells out to `forge`, which was absent from its PATH. It died with
   FileNotFoundError and the parser read the traceback as "no failures".
3. halmos reads the Solidity AST from build artifacts. Running `forge build`
   first wrote artifacts without an AST, so halmos skipped every file with
   "KeyError: 'ast'", found no tests, and exited quietly. foundry.toml now sets
   `ast = true`, and `assert_ran` refuses to draw any conclusion from a run that
   produced no result line.

Defect 3 is the one worth remembering: for two runs the pipeline was reporting a
clean formal verification pass while verifying literally nothing.

## Also fixed this phase

forge lint flagged unchecked ERC20 transfer return values in OrderBookVenue. Real
finding, not noise: a token returning false rather than reverting would let a fill
record itself while no value moved. All eight call sites now route through checked
`_pull` and `_push` helpers that revert with `TransferFailed`. 27 contract tests
still green after the change.
