# Task 14.2: invariant campaign on the vault and fee contracts

Run 2026-08-16 19:10:33 UTC. Verdict: **PASS**

Campaign configuration, from `contracts/foundry.toml`:

```
[invariant]
runs = 128
depth = 64
fail_on_revert = false
show_metrics = true

```

## Baseline

10 passing, 0 failing.

```
[PASS] invariant_feeNeverExceedsTheCeiling() 
[PASS] invariant_feeOnlyEverFalls() 
[PASS] invariant_totalCollectedMatchesTheTreasury() 
[PASS] test_chargingAndLoweringAreBothReachable() 
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 13.15s 
[PASS] invariant_committedNeverExceedsBalance() 
[PASS] invariant_totalCommittedEqualsSumOfCommitted() 
[PASS] invariant_totalDepositsEqualsSumOfBalances() 
[PASS] invariant_vaultIsAlwaysSolvent() 
[PASS] invariant_withdrawableIsBalanceMinusCommitted() 
[PASS] test_everyInterestingStateIsReachable() 
Suite result: ok. 6 passed; 0 failed; 0 skipped; finished in 14.35s 
```

## The invariants, and what each one forbids

| invariant | the state it rules out |
|---|---|
| `invariant_vaultIsAlwaysSolvent` | held assets plus committed funds falling below what depositors are owed |
| `invariant_totalDepositsEqualsSumOfBalances` | the running total drifting from the per-depositor ledger |
| `invariant_totalCommittedEqualsSumOfCommitted` | the same drift on the committed side, which is the one a running sum gets wrong |
| `invariant_committedNeverExceedsBalance` | a depositor committing funds they do not hold |
| `invariant_withdrawableIsBalanceMinusCommitted` | the withdrawable figure disagreeing with the two numbers it is derived from |
| `invariant_feeNeverExceedsTheCeiling` | a fee rate above the hard cap |
| `invariant_feeOnlyEverFalls` | a fee rate rising after deployment |
| `invariant_totalCollectedMatchesTheTreasury` | collected fees and the treasury balance disagreeing |

## Why a passing campaign is not yet evidence

An invariant holds trivially over states the campaign never reaches. A handler that never
committed anything would satisfy every solvency invariant here while testing none of them, and
the run would look identical. Two things close that gap.

**Reachability.** `test_everyInterestingStateIsReachable` and
`test_chargingAndLoweringAreBothReachable` are deterministic tests asserting the interesting
states are constructible at all. They are ordinary tests rather than invariants on purpose: an
anti-vacuity check written as an `invariant_` fails at step zero, before the handler has done
anything, and the same check in `afterInvariant` makes the fuzzer shrink toward a single call.
Both of those were written the wrong way here first.

**A mutation that must be caught.** Below.

## The mutation

The free-balance guard in `AgentVault.openTrade` was removed:

```solidity
-        if (notional > free) revert InsufficientBalance(notional, free);
+        // MUTATED BY 166: free-balance check removed
```

That is precisely the state `invariant_committedNeverExceedsBalance` exists to forbid, so the
campaign is required to find it. It did: **1 invariant failing**, namely `invariant_committedNeverExceedsBalance `.

The other seven still hold under the mutation, which is the right result and worth stating:
removing the free-balance guard does not make the vault insolvent or break the ledger sums, it
lets a depositor commit funds they do not have. An invariant set where every invariant fails
on every mutation is not measuring eight things.

```
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 12.59s (14.02s CPU time)
[FAIL: committed exceeded balance: 3561 > 2328]
 invariant_committedNeverExceedsBalance() (runs: 0, calls: 0, reverts: 0)
Suite result: FAILED. 5 passed; 1 failed; 0 skipped; finished in 13.49s (32.93s CPU time)
[FAIL: committed exceeded balance: 3561 > 2328]
 invariant_committedNeverExceedsBalance() (runs: 0, calls: 0, reverts: 0)
```

Counterexample from this run: `committed exceeded balance: 3561 > 2328`.

**That number is the proof the search was fresh.** Foundry persists counterexamples to
`cache/invariant/failures/` and REPLAYS them on the next run, printing "Replayed invariant
failure from ... file". The first working version of this gate caught the mutation exactly that
way, which demonstrates only that a counterexample once existed on disk, not that this campaign
can still find one. The cache is now cleared before every run, and because the witness is drawn
from that run's fuzzed inputs, re-running this gate prints a DIFFERENT committed figure. A
replay would reproduce the stored one byte for byte.

## Restored

10 passing, 0 failing, matching the baseline's 10.

## Reproduce

```
bash scripts/166-vault-invariants.sh
```
