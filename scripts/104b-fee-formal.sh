#!/usr/bin/env bash
# Task 7.4: symbolic theorems about the fee.
#
# EVIDENCE PATH: evidence/phase7/fee-formal.txt
# PASS: all theorems pass AND the run reports a NON-ZERO test count.
#
# The named fake win, quoted from TASKS.md: "halmos reporting '0 tests found' and exiting 0, which has
# happened in this project before." The counter: the executed-theorem count is asserted against the
# number declared in the source before any pass is trusted.
#
# THEOREMS RUN ONE AT A TIME, with a wall-clock timeout each. The first version ran all five in one
# invocation with --solver-timeout-assertion 0, and a single stalling theorem produced 25 minutes of
# silence with no output for the four that were fine. Per-theorem isolation means a stall is
# attributable and reports as a failure rather than as a hang.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase7/fee-formal.txt"
mkdir -p "$(dirname "$OUT")"
cd "$REPO/contracts"

SRC=test/FeeFormal.t.sol
THEOREMS=$(grep -oE '^    function (check_[a-zA-Z0-9_]+)' "$SRC" | awk '{print $2}')
DECLARED=$(printf '%s\n' "$THEOREMS" | grep -c .)

{
  echo "Task 7.4, symbolic fee theorems"
  echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "halmos: $(halmos --version 2>&1 | head -1)"
  echo "theorems declared in $SRC: $DECLARED"
  printf '%s\n' "$THEOREMS" | sed 's/^/  - /'
} > "$OUT"

PROVED=0
BROKEN=0
STALLED=0

for T in $THEOREMS; do
  LOG=$(mktemp)
  START=$(date +%s)
  # halmos colours its verdicts, so the log is stripped of ANSI escapes before anything greps it.
  # Without this the PASS match fails on every line and five proved theorems read as five failures,
  # which is exactly the direction of error that must never be silent.
  timeout 600 halmos --contract FeeFormalTest --function "$T" \
    --solver-timeout-assertion 240000 2>&1 | sed -r 's/\x1B\[[0-9;]*[mK]//g' > "$LOG"
  RC=${PIPESTATUS[0]}
  ELAPSED=$(( $(date +%s) - START ))

  {
    echo
    echo "== $T =="
    grep -E '^\[(PASS|FAIL|TIMEOUT)\]|Counterexample|Symbolic test result' "$LOG" | sed 's/^/  /'
    echo "  elapsed: ${ELAPSED}s, exit: $RC"
  } >> "$OUT"

  # A solver TIMEOUT is not a proof. halmos reports it distinctly and it is counted as a stall, never
  # folded into the pass count.
  if [ "$RC" -eq 124 ] || grep -q "^\[TIMEOUT\] $T" "$LOG"; then
    STALLED=$((STALLED + 1))
    echo "  VERDICT: STALLED, no proof obtained. Counted as a failure, not as a pass." >> "$OUT"
  elif [ "$RC" -eq 0 ] && grep -q "^\[PASS\] $T" "$LOG"; then
    PROVED=$((PROVED + 1))
    echo "  VERDICT: PROVED" >> "$OUT"
  else
    BROKEN=$((BROKEN + 1))
    echo "  VERDICT: FAILED. Counterexample or error above." >> "$OUT"
    grep -A6 'Counterexample' "$LOG" | sed 's/^/    /' >> "$OUT"
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

tail -45 "$OUT"
