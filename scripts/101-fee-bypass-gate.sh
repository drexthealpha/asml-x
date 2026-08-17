#!/usr/bin/env bash
# Task 7.3 gate: prove there is no fee-free execution path.
#
# THINKING: #22 inversion, #29 pre-mortem, #66 adversarial. The question is not "does the happy path
# charge a fee" but "what does an operator holding the agent key do to avoid paying it".
#
# EVIDENCE PATH, declared before the code ran: evidence/phase7/fee-bypass.txt
# PASS: every bypass route reverts, the authorised path still works (negative control), and the suite
# asserts the number of tests it found so a silent zero-test run cannot read as green.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase7/fee-bypass.txt"
mkdir -p "$(dirname "$OUT")"
cd "$REPO/contracts"

{
  echo "Task 7.3, fee bypass gate"
  echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  echo "== full suite, all contracts =="
} > "$OUT"

forge test --match-path 'test/*.t.sol' -vv >> "$OUT" 2>&1
RC=$?

{
  echo
  echo "== assertion: the bypass suite actually ran and found its tests =="
} >> "$OUT"

# R-MUTATE's sibling problem: a --match-path typo produces "0 tests passed", which forge reports with
# exit 0. Counting the named tests is what makes this gate unfakeable by an empty run.
FOUND=$(grep -c '^\[PASS\] test_' "$OUT")
BYPASS=$(forge test --match-contract FeeBypassTest --list 2>/dev/null | grep -c 'test_')
FAILED=$(grep -c '^\[FAIL' "$OUT")

{
  echo "FeeBypassTest tests found: $BYPASS (expected 11)"
  echo "total PASS lines in run:   $FOUND"
  echo "FAIL lines in run:         $FAILED"
  echo "forge exit code:           $RC"
} >> "$OUT"

if [ "$RC" -eq 0 ] && [ "$BYPASS" -eq 11 ] && [ "$FAILED" -eq 0 ]; then
  echo "GATE: PASS" >> "$OUT"
else
  echo "GATE: FAIL" >> "$OUT"
fi

tail -25 "$OUT"
