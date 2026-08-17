# Phase 7 gate: a live onchain business model

Closed 2026-08-15. Chain 1952. Every gate below was run, not asserted.

**CLOCK STOPS HERE (TASKS.md):** an agent with a live onchain business model on testnet.
No user can touch it yet. That is Phase 8 and 9.

## Subtasks

| # | task | gate | verdict |
|---|---|---|---|
| 7.1 | fee pattern research | `bash scripts/100-fee-pattern-research.sh` | PASS, 4 sources reachable, 1 pattern rejected |
| 7.2 | FeeCollector | `forge test --match-contract FeeCollectorTest` | PASS, 8 tests |
| 7.3 | fee unskippable | `bash scripts/101-fee-bypass-gate.sh` | PASS, 74 of 74 tests, 11 bypass tests |
| 7.3 | mutation on the bypass | `bash scripts/102-fee-bypass-mutation.sh` | PASS, both enforcement lines load-bearing |
| 7.4 | symbolic theorems | `bash scripts/104b-fee-formal.sh` | PASS, 5 of 5 proved |
| 7.5 | mutation on the fee | `bash scripts/104-fee-mutation.sh` | PASS, 6 of 6 killed |
| 7.6 | live fee event | `bash scripts/105-fee-live-testnet.sh` | PASS, real tx, decoded from receipt |
| 7.7 | fees reach the UI from chain | `bash scripts/107-fee-ui-gate.sh` | PASS, checks A, B and C |
| 7.8 | adversarial audit | `bash scripts/109-phase7-redteam.sh` | PASS, 3 attacks failed on live bytecode |

Claims C-701 through C-709 in evidence/CHAIN-OF-EVIDENCE.md.

## What is live on chain 1952

| contract | address |
|---|---|
| FeeCollector | `0x367FC329469497Ac87FA19Fb34dE4595610b381A` |
| BatchExecutor | `0xad717b52AbD5bf15955E407cEb8d49FA19fA3e95` |
| OrderBookVenue | `0x2C59E586FcDAA3e923691Ee5DC7eeF5941f2b720` |
| RiskGuard | `0x41EBF630E206Fe911cECa2E7527b1d227C224726` |

Revenue to date: 0.2 tQUOTE over 2 charges at 50 bps, on 40 tQUOTE of notional.
Fee tx: `0xd49391a1404815b742c7f6f25bce763bc18f77eebb8534835ef8785f1097a5c5`

## FAKE WIN REGISTER, and what was actually done about each

Every fake win TASKS.md named for this phase, with the counter-task and whether it fired.

| named fake win | counter | fired? |
|---|---|---|
| 7.1 citing a blog and calling it research | probe each source for reachability; reject a pattern that was genuinely considered | No. All 4 sources returned 200, and the performance-fee model was rejected with a specific disqualifier: zero realized PnL means zero fee events for the whole demo. |
| 7.2 an event carrying values the TEST computed | expectations written against the contract's own `quoteFee` | No. |
| 7.3 a test that only exercises the executor, leaving the venue reachable behind it | attempt the bypass directly against the venue | **YES, and it was real.** `OrderBookVenue.take` was `external` with no access control and the contract had no owner. The agent key could fill any order directly, skipping the fee AND the RiskGuard. Closed by an authorised-taker list. |
| 7.4 halmos reporting "0 tests found" and exiting 0 | assert the discovered count before trusting the pass | **YES, in a new form.** The first run passed 4 theorems and my own grep failed to strip halmos's ANSI codes, reporting 0 proved of 5. A 5th genuinely TIMEOUT-ed and would have been counted as passing had the exit code been trusted. Timeouts are now counted as stalls, never as proofs. |
| 7.5 mutating something no test covers and calling the green a success | a surviving mutant is a FINDING, listed not scored | **YES.** M2 survived. It was not a missing test: the ceiling check inside `setFeeBps` was unreachable dead code. Deleted from the contract rather than covered by an unreachable test. |
| 7.6 reading the fee from the local journal instead of the receipt | decode from `eth_getTransactionReceipt` | No, and the cross-check caught something else: treasury == maker == deployer, so 20e18 of trade proceeds and 0.1e18 of fee landed in one balance. Revenue could not be stated from balances at all. Separate treasury assigned. |
| 7.7 **the phase headline**, a counter incremented in TypeScript on each decision | no-data proof plus a grep asserting no fee arithmetic in `ui-v2/src` | No. The checker itself is mutation-tested: it must catch an injected `feeA + feeB` or CHECK A fails. |
| 7.8 an audit that describes attacks instead of running them | run all three against live bytecode | No, but the first run's COUNTERFACTUAL was wrong: it claimed order 0 was live when `remainingBase` was 0. A revert against an unfillable order proves nothing about authorisation. The target order is now chosen by reading the venue. |

## Defects found by these gates that no task asked for

1. **Three separate hardcoded address sites** were serving an abandoned deployment after 7.6: the
   metrics shell script, the metrics JSON writer, and the UI contract manifest. The dashboard was
   rendering one deployment's addresses beside another's numbers. All three now derive from
   `deployments.json` or `docs/verified/deployments.md`, and the deploy script regenerates the UI
   manifest so it cannot drift again.
2. **A zero-manufacturing fallback.** `cast logs ... || echo '[]'` turned an RPC rejection into an
   empty array that read downstream as "zero fees collected", defeating a guard written three lines
   away for exactly that purpose. Removed; a failed read now fails the build.
3. **X Layer's RPC caps `eth_getLogs` at 100 blocks** (`-32602`), so the naive scan never worked.
   Totals now come from contract state, which theorem 5 proves equals the sum of events, and detail
   rows from a cursor-backed bounded scan: 106 windows cold, 3 warm.
4. **The executor could not grant its own token allowances on chain.** Tests used
   `vm.prank(address(exec))`, a cheat with no onchain equivalent. Found by writing the deploy script,
   not by running the suite. `approveToken` added, and the per-batch approve legs removed with it:
   gas per execution fell from 263,036 to 199,448, measured.

## Not claimed

The owner key can appoint chargers and lower the fee. An owner who loses that key loses those powers
to whoever holds it. That is a key-custody property rather than a contract property, and Phase 8 is
where custody gets an answer.
