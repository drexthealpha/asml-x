# Phase 8 gate: personal capital, with custody proven

Closed 2026-08-15. Chain 1952. Every gate below was run, not asserted.

**CLOCK STOPS HERE (TASKS.md):** user funds can exist, be limited, be paused and be withdrawn,
all proven onchain. Still CLI-only. A judge cannot feel it. That is Phase 9.

## Subtasks

| # | task | gate | verdict |
|---|---|---|---|
| 8.1 | custody and pause research | `bash scripts/111-vault-research.sh` | PASS, 3 sources reachable, 2 patterns rejected |
| 8.2 | AgentVault | `bash scripts/112b-vault-tests.sh` | PASS, 18 of 18 |
| 8.3 | per-user limits, two enforcements | `bash scripts/112d-per-user-limits.sh` | PASS, 6 Rust tests + a reverted testnet tx |
| 8.4 | formal custody properties | `bash scripts/112e-vault-formal.sh` | PASS, 6 of 6 proved |
| 8.5 | mutation gate | `bash scripts/112-vault-mutation.sh` | PASS, 7 of 7 killed |
| 8.6 | live deposit, trade, withdraw | `bash scripts/113-vault-live.sh` | PASS, 3 tx at 0x1, custody exact |
| 8.7 | pause mid-cycle | `bash scripts/114-pause-under-load.sh` | PASS, block ordering proves mid-flight |
| 8.8 | adversarial audit | `bash scripts/115-phase8-redteam.sh` | PASS, 4 attacks failed on live bytecode |

Claims C-800 through C-807.

## Live on chain 1952

| contract | address |
|---|---|
| AgentVault | `0xdF6f9503aE4e941F6055A945d940602FD729388F` |

Deployed at block 38341805's successor set; vault deploy block recorded in `deployments.json`.
Asset `tQUOTE`, trade target the OrderBookVenue, both immutable.

## The one property this phase exists for

Tokens leave `AgentVault` only to the address that deposited them, and only when that address asks.
No owner withdrawal, no agent withdrawal, no rescue, no sweep, no upgrade path. Every one of those
would be an operator exit, and a custody contract with an operator exit is a custody claim with an
asterisk.

Pause constrains the AGENT and never the depositor. A pause that could trap funds would turn the
safety feature into the attack, which is the failure the pausable audit guidance names as a major
red flag.

## FAKE WIN REGISTER, and what was actually done about each

| named fake win | counter | fired? |
|---|---|---|
| 8.1 research that concludes exactly what was already planned | the rejected pattern must be one genuinely considered | **YES.** ERC-4626 was the intended design before this task. Rejected because shares price a pool and there is no pool. A second pattern, a withdrawal delay queue, was also rejected on the griefing evidence. |
| 8.2 testing withdraw only from the depositor's address | test the agent key, the owner key and a random key | No. And the stronger form was added: every state-changing function walked, none moves funds to a caller-named address. |
| 8.3 enforcing only offchain and calling it structural | demonstrate the onchain revert with a real testnet transaction | No. A submitted transaction landed reverted with status 0x0 at block 38356671, with a passing within-limit counterfactual beside it. |
| 8.4 proving a property vacuously true because its precondition is unreachable | mutation-test each theorem in 8.5 | **YES, and this was the most valuable finding in the phase.** See below. |
| 8.5 a high kill rate with survivors unexamined | list survivors individually with a judgement | No survivors, but the gate's own design was wrong first. See below. |
| 8.6 a withdrawal returning a different amount without saying why | assert the balance delta and print the fee explaining any difference | **YES.** The first run showed a 2 tQUOTE wallet delta. It was neither a loss nor dust. |
| 8.7 pausing an idle agent and calling it a circuit breaker | the pause must land mid-flight, proven by block numbers | No. Open at 38358088 with funds committed, pause at 38358109, close at 38358137. |
| 8.8 an audit that describes attacks instead of running them | run all four against live bytecode | No. All four ran against the deployed contract with decoded revert selectors. |

## The vacuity finding, in full

Task 8.4 reported 6 of 6 theorems PROVED. Task 8.5's mutant M1 rewrites `_withdraw(msg.sender, ...)`
to `_withdraw(tx.origin, ...)`, which credits the wrong address on every withdrawal. Four unit tests
caught it. **All six theorems still proved.**

The cause is a property of symbolic execution, not of the mutation. Under the mutant a depositor's
`withdrawAll` ends up withdrawing for an address with no balance, so the call REVERTS, and a reverting
path is DISCARDED by the solver rather than counted as a violated assertion. Every assertion after the
call simply never ran. `check_vaultDepositorCanAlwaysWithdrawEvenWhenPaused` asserted what a
successful withdrawal returns and never that the withdrawal succeeds at all.

"A depositor can ALWAYS withdraw" is a liveness claim, and a liveness claim has to rule out the revert
explicitly. Every positive theorem now wraps its call in `try/catch` with `assert(false)` in the
catch. After the fix M1 is caught by two theorems, and M7, which adds a pause check to the withdrawal
path, is caught by the theorem written to forbid exactly that.

This is also a finding about the GATE. The first version named one expected theorem per mutant and ran
only that, so a mutant caught by a different theorem was indistinguishable from a mutant caught by
none. It now runs all six against every mutant and reports the set that stopped proving.

## Known gap, stated rather than confessed

Mutant M6 reintroduces the fee-on-transfer credit bug and is killed by a unit test but by **no
theorem**. That is expected and not a defect: the symbolic suite uses an honest `SymToken`, so no
theorem models a token that delivers less than it claims. Closing it would mean a symbolic token with
arbitrary transfer behaviour, which is a materially larger proof obligation than this phase needs. The
concrete test `test_aShortDeliveringTokenCannotCreditABalanceTheVaultDoesNotHold` covers it, and the
contract credits the measured balance delta rather than the requested amount, so the accounting cannot
be corrupted even though the property is checked by example rather than by proof.

## Defects found by these gates that no task asked for

1. **`isSolvent()` would have lied.** `totalCommitted` was declared and never written, so the solvency
   check returned false for any vault with an open trade while the vault was perfectly solvent. A
   solvency number that reads wrong is worse than none, because it is the number an operator points at.
2. **An externally reachable `withdrawFor(address,uint256)`** existed in the first draft, self-call
   restricted so `withdrawAll` could reuse it. Its safety rested on one `msg.sender == address(this)`
   line. Replaced with a private function before deployment; the deployed ABI has no such surface.
3. **An unsafe `int256` cast** in the `TradeClosed` event, flagged by forge-lint. The operands come
   from a token this contract does not control, so the usual "this cast is safe because" annotation
   would have read "because I assume the token behaves", which is the assumption the balance-delta
   pattern exists to avoid. The event now carries the two raw amounts.
4. **A symbolic theorem was unfunded.** `closeTrade` settles from `msg.sender`, and the formal suite
   never minted tokens to the agent, so the reachability theorem failed for a reason belonging to the
   test rather than the contract. Found by reading a solver trace rather than by guessing.

## Not claimed

The vault owner can rotate the agent. A rotated agent inherits the same three gates and gains nothing,
but an owner who loses their key hands rotation to whoever holds it. That is key custody, not contract
custody, and it is bounded: no agent, rotated or original, can withdraw a depositor's funds.

A depositor can raise their own limit. That is intended. No key can raise anyone else's, and the
offchain engine's own limits still bind on top, proved by
`prop_a_user_limit_can_never_widen_what_the_system_allows`.
