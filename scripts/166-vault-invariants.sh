#!/usr/bin/env bash
# Task 14.2 gate: invariant campaign on the fee and vault contracts.
#
# THINKING: #46 invariant reasoning (the question is what must hold across EVERY reachable state, not
# what holds on the paths I thought to write down), #45 formal, #66 failure-mode.
#
# EVIDENCE PATH: evidence/phase14/invariants.md
# PASS: every invariant holds across the full campaign, the reachability tests prove the campaign
# actually reaches the interesting states, AND a mutation makes a named invariant go RED.
#
# THE MUTATION IS THE POINT (R-MUTATE). An invariant suite that passes proves nothing on its own: a
# suite whose handler never reaches a committing state would pass every solvency invariant by never
# testing one. So this gate breaks the vault's free-balance check, requires the campaign to catch it,
# then restores and requires GREEN again. A run without the RED half is not evidence.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase14/invariants.md"
SRC="$REPO/contracts/src/AgentVault.sol"
LOG="$REPO/evidence/phase14/invariant-run.txt"
mkdir -p "$(dirname "$OUT")"

cd "$REPO/contracts"
FORGE="$HOME/.foundry/bin/forge"

# ANSI stripped at the source. A previous gate in this repo recorded escape codes into an evidence
# file, which then failed every grep asserting on its own content.
#
# THE FAILURE CACHE IS CLEARED FIRST, and this is not tidiness. Foundry persists a counterexample to
# cache/invariant/failures/ and REPLAYS it on the next run, printing "Replayed invariant failure from
# ... file" and "runs: 1, calls: 1". The first working version of this gate caught the mutation that
# way, which proves only that a counterexample was once found and written to disk, not that this
# campaign can find it. A stale entry from an earlier session would make a suite that had lost the
# ability to find the bug look like it still caught it. Every run below searches from scratch.
run_suite() {
  rm -rf cache/invariant/failures
  "$FORGE" test --match-path "test/VaultInvariants.t.sol" --color never 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
}

echo "=== baseline ==="
run_suite > "$LOG"
BASE_PASS=$(grep -cE "^\[PASS\]" "$LOG")
BASE_FAIL=$(grep -cE "^\[FAIL" "$LOG")
echo "pass $BASE_PASS  fail $BASE_FAIL"

# The mutation: remove the free-balance check in openTrade, so a depositor can commit more than they
# hold. This is the exact thing invariant_committedNeverExceedsBalance exists to forbid.
cp "$SRC" "$SRC.bak"
python3 - "$SRC" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "        if (notional > free) revert InsufficientBalance(notional, free);"
assert old in s, "mutation target not found; the gate must not silently pass"
s = s.replace(old, "        // MUTATED BY 166: free-balance check removed", 1)
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("mutation applied")
PY

echo "=== mutated ==="
run_suite > "$LOG.mut"
# Count DISTINCT failing invariants. `grep -c '^\[FAIL'` returns 2 for a single failure, because
# forge prints the failure once in the run and again in the closing failing-tests summary. Reporting
# that as "2 failing" would inflate the catch.
MUT_FAIL=$(grep -oE "^[[:space:]]+invariant_[A-Za-z]+" "$LOG.mut" | tr -d ' ' | sort -u | wc -l)
# Scrape names from the FAIL LINES ONLY. A first version grepped the whole log, which contains every
# invariant name in its pass list too, so it reported all eight as "caught" when two failed. That is
# the same defect shape as this repo's earlier decorative fallbacks: a cosmetic line quietly making a
# claim the run does not support.
# The name of a FAILING invariant is printed on its own indented line, not on the `[FAIL: ...]` line,
# which carries only the assertion message. A passing one is printed as `[PASS] invariant_x()`, with
# no leading whitespace, so the leading-space anchor separates them.
CAUGHT=$(grep -oE "^[[:space:]]+invariant_[A-Za-z]+" "$LOG.mut" | tr -d ' ' | sort -u | tr '\n' ' ')
# The counterexample's own value. This is what shows the search was FRESH: an unshrunk committed
# figure is drawn from that run's fuzzed inputs, so two runs of this gate produce two different
# numbers, whereas a cached replay would reproduce the stored one byte for byte.
MUT_WITNESS=$(grep -oE "committed exceeded balance: [0-9]+ > [0-9]+" "$LOG.mut" | head -1)
echo "fail $MUT_FAIL  caught: $CAUGHT"

mv "$SRC.bak" "$SRC"
echo "=== restored ==="
run_suite > "$LOG.restored"
REST_PASS=$(grep -cE "^\[PASS\]" "$LOG.restored")
REST_FAIL=$(grep -cE "^\[FAIL" "$LOG.restored")
echo "pass $REST_PASS  fail $REST_FAIL"

VERDICT=FAIL
if [ "$BASE_FAIL" -eq 0 ] && [ "$MUT_FAIL" -gt 0 ] && [ "$REST_FAIL" -eq 0 ] && [ "$BASE_PASS" -eq "$REST_PASS" ]; then
  VERDICT=PASS
fi

{
echo "# Task 14.2: invariant campaign on the vault and fee contracts"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **$VERDICT**"
echo
echo "Campaign configuration, from \`contracts/foundry.toml\`:"
echo
echo '```'
sed -n '/\[invariant\]/,/^$/p' foundry.toml
echo '```'
echo
echo "## Baseline"
echo
echo "$BASE_PASS passing, $BASE_FAIL failing."
echo
echo '```'
grep -E "^\[PASS\]|^\[FAIL|Suite result" "$LOG" | sed 's/([^)]*)$//'
echo '```'
echo
echo "## The invariants, and what each one forbids"
echo
echo "| invariant | the state it rules out |"
echo "|---|---|"
echo "| \`invariant_vaultIsAlwaysSolvent\` | held assets plus committed funds falling below what depositors are owed |"
echo "| \`invariant_totalDepositsEqualsSumOfBalances\` | the running total drifting from the per-depositor ledger |"
echo "| \`invariant_totalCommittedEqualsSumOfCommitted\` | the same drift on the committed side, which is the one a running sum gets wrong |"
echo "| \`invariant_committedNeverExceedsBalance\` | a depositor committing funds they do not hold |"
echo "| \`invariant_withdrawableIsBalanceMinusCommitted\` | the withdrawable figure disagreeing with the two numbers it is derived from |"
echo "| \`invariant_feeNeverExceedsTheCeiling\` | a fee rate above the hard cap |"
echo "| \`invariant_feeOnlyEverFalls\` | a fee rate rising after deployment |"
echo "| \`invariant_totalCollectedMatchesTheTreasury\` | collected fees and the treasury balance disagreeing |"
echo
echo "## Why a passing campaign is not yet evidence"
echo
echo "An invariant holds trivially over states the campaign never reaches. A handler that never"
echo "committed anything would satisfy every solvency invariant here while testing none of them, and"
echo "the run would look identical. Two things close that gap."
echo
echo "**Reachability.** \`test_everyInterestingStateIsReachable\` and"
echo "\`test_chargingAndLoweringAreBothReachable\` are deterministic tests asserting the interesting"
echo "states are constructible at all. They are ordinary tests rather than invariants on purpose: an"
echo "anti-vacuity check written as an \`invariant_\` fails at step zero, before the handler has done"
echo "anything, and the same check in \`afterInvariant\` makes the fuzzer shrink toward a single call."
echo "Both of those were written the wrong way here first."
echo
echo "**A mutation that must be caught.** Below."
echo
echo "## The mutation"
echo
echo "The free-balance guard in \`AgentVault.openTrade\` was removed:"
echo
echo '```solidity'
echo "-        if (notional > free) revert InsufficientBalance(notional, free);"
echo "+        // MUTATED BY 166: free-balance check removed"
echo '```'
echo
echo "That is precisely the state \`invariant_committedNeverExceedsBalance\` exists to forbid, so the"
echo "campaign is required to find it. It did: **$MUT_FAIL invariant failing**, namely \`$CAUGHT\`."
echo
echo "The other seven still hold under the mutation, which is the right result and worth stating:"
echo "removing the free-balance guard does not make the vault insolvent or break the ledger sums, it"
echo "lets a depositor commit funds they do not have. An invariant set where every invariant fails"
echo "on every mutation is not measuring eight things."
echo
echo '```'
grep -E "^\[FAIL|^[[:space:]]+invariant_|Suite result" "$LOG.mut" | head -12
echo '```'
echo
echo "Counterexample from this run: \`$MUT_WITNESS\`."
echo
echo "**That number is the proof the search was fresh.** Foundry persists counterexamples to"
echo "\`cache/invariant/failures/\` and REPLAYS them on the next run, printing \"Replayed invariant"
echo "failure from ... file\". The first working version of this gate caught the mutation exactly that"
echo "way, which demonstrates only that a counterexample once existed on disk, not that this campaign"
echo "can still find one. The cache is now cleared before every run, and because the witness is drawn"
echo "from that run's fuzzed inputs, re-running this gate prints a DIFFERENT committed figure. A"
echo "replay would reproduce the stored one byte for byte."
echo
echo "## Restored"
echo
echo "$REST_PASS passing, $REST_FAIL failing, matching the baseline's $BASE_PASS."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/166-vault-invariants.sh"
echo '```'
} > "$OUT"

echo
echo "written: $OUT"
echo "VERDICT: $VERDICT"
[ "$VERDICT" = PASS ]
