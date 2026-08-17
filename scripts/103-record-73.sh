#!/usr/bin/env bash
# Append the chain-of-evidence rows for tasks 7.1 through 7.3.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
D=$(date -u '+%Y-%m-%d')
CoE="$REPO/evidence/CHAIN-OF-EVIDENCE.md"

cat >> "$CoE" <<MD
| C-701 | The fee model was chosen against four reachable primary sources (all four returned 200 on probe) and one named pattern, a performance fee on realized PnL, was REJECTED with its specific disqualifier: this agent has zero closed positions with settled profit, so that model would emit zero fee events for the whole demo | evidence/phase7/fee-research.md | bash scripts/100-fee-pattern-research.sh | DEMONSTRATED | 7.1 | $D |
| C-702 | FeeCollector charges a usage fee bounded by an immutable 100 bps ceiling that setFeeBps can only ever lower, accounts on the observed balance delta rather than the amount argument, and reverts rather than under-collecting against a token that keeps 10 percent in transit, reproducing the Code4rena Cudos 2022 issue 3 failure as a live test | contracts/src/FeeCollector.sol, contracts/test/FeeCollector.t.sol | cd contracts && forge test --match-contract FeeCollectorTest | DEMONSTRATED | 7.2 | $D |
| C-703 | There is no fee-free execution path. OrderBookVenue.take was external with no access control and no owner, so the agent key could fill any resting order directly, skipping both the fee and the RiskGuard; it is now restricted to authorised takers. BatchExecutor now requires the last leg to target its immutable feeCollector, so a batch with no fee leg, a fee leg that is not last, and a fee leg pointed at an impostor collector all revert. Eleven bypass tests, funded and fully approved agent key, five enumerated routes, plus a negative control proving the authorised path still fills | evidence/phase7/fee-bypass.txt, contracts/test/FeeBypass.t.sol | bash scripts/101-fee-bypass-gate.sh | DEMONSTRATED | 7.3 | $D |
| C-704 | Both fee-bypass enforcement lines are load-bearing: deleting the authorised-taker check turns the suite RED with 4 failures, deleting the last-leg check turns it RED with 3, and the restored source returns to 22 of 22 GREEN | evidence/phase7/fee-bypass-mutation.txt | bash scripts/102-fee-bypass-mutation.sh | DEMONSTRATED | 7.3 | $D |
MD

echo "rows now: $(grep -c '^| C-' "$CoE")"
tail -2 "$CoE" | cut -c1-90
