#!/usr/bin/env bash
# Task 8.4: symbolic custody theorems.
#
# EVIDENCE PATH: evidence/phase8/vault-formal.txt
# PASS: all theorems pass with a non-zero discovered-test count.
#
# Same runner shape as task 7.4's, for the reasons that task paid for: theorems run ONE AT A TIME
# with a wall-clock timeout each, ANSI is stripped before anything greps the log, and a halmos
# TIMEOUT is counted as a stall rather than folded into the pass count. A timeout is not a proof.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase8/vault-formal.txt"
mkdir -p "$(dirname "$OUT")"
cd "$REPO/contracts"

SRC=test/VaultFormal.t.sol
THEOREMS=$(grep -oE '^    function (check_[a-zA-Z0-9_]+)' "$SRC" | awk '{print $2}')
DECLARED=$(printf '%s\n' "$THEOREMS" | grep -c .)

{
echo "Task 8.4, symbolic custody theorems"
echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "halmos: $(halmos --version 2>&1 | head -1)"
echo "theorems declared in $SRC: $DECLARED"
printf '%s\n' "$THEOREMS" | sed 's/^/  - /'
} > "$OUT"

PROVED=0; BROKEN=0; STALLED=0

for T in $THEOREMS; do
  LOG=$(mktemp)
  START=$(date +%s)
  timeout 600 halmos --contract VaultFormalTest --function "$T" \
    --solver-timeout-assertion 240000 2>&1 | sed -r 's/\x1B\[[0-9;]*[mK]//g' > "$LOG"
  RC=${PIPESTATUS[0]}
  ELAPSED=$(( $(date +%s) - START ))

  {
    echo
    echo "== $T =="
    grep -E '^\[(PASS|FAIL|TIMEOUT|ERROR)\]|Counterexample|Symbolic test result' "$LOG" | sed 's/^/  /'
    echo "  elapsed: ${ELAPSED}s, exit: $RC"
  } >> "$OUT"

  if [ "$RC" -eq 124 ] || grep -q "^\[TIMEOUT\] $T" "$LOG"; then
    STALLED=$((STALLED + 1))
    echo "  VERDICT: STALLED, no proof obtained. Counted as a failure." >> "$OUT"
  elif [ "$RC" -eq 0 ] && grep -q "^\[PASS\] $T" "$LOG"; then
    PROVED=$((PROVED + 1))
    echo "  VERDICT: PROVED" >> "$OUT"
  else
    BROKEN=$((BROKEN + 1))
    echo "  VERDICT: FAILED" >> "$OUT"
    grep -A8 'Counterexample' "$LOG" | sed 's/^/    /' >> "$OUT"
    grep -E 'Error|error' "$LOG" | head -4 | sed 's/^/    /' >> "$OUT"
  fi
  rm -f "$LOG"
done

{
echo
echo "== gate =="
echo "declared: $DECLARED"
echo "proved:   $PROVED"
echo "failed:   $BROKEN"
echo "stalled:  $STALLED"
if [ "$PROVED" -eq "$DECLARED" ] && [ "$DECLARED" -gt 0 ]; then
  echo "GATE: PASS  $PROVED of $DECLARED theorems proved, none skipped and none stalled"
else
  echo "GATE: FAIL  proved=$PROVED of declared=$DECLARED (failed=$BROKEN stalled=$STALLED)"
fi
} >> "$OUT"

tail -50 "$OUT"

# EXIT ON THE VERDICT, for the same reason as scripts/104b-fee-formal.sh: this script printed its
# verdict and then exited 0 regardless, because the last command was the `tail` above. A CI job
# built on that would go green while the gate said theorems were unproved.
[ "$PROVED" -eq "$DECLARED" ] && [ "$DECLARED" -gt 0 ]
