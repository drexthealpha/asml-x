#!/usr/bin/env bash
# Task 0.7 / 2.6 / 10.1 / 12.7: re-run every command in CHAIN-OF-EVIDENCE.md and confirm
# its evidence artifact exists.
#
# This is the mechanism that makes "a claim with no evidence path gets deleted" real rather
# than aspirational. --dry lists what would run without running it.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

INDEX="$REPO/evidence/CHAIN-OF-EVIDENCE.md"
DRY=0
[ "${1:-}" = "--dry" ] && DRY=1

if [ ! -f "$INDEX" ]; then
  echo "MISSING INDEX: $INDEX"
  exit 1
fi

OUT="$REPO/evidence/chain-verify-report.md"
{
  echo "# Chain verification report"
  echo
  echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). dry=$DRY"
  echo
  echo "| id | evidence exists | command | result |"
  echo "|---|---|---|---|"
} > "$OUT"

TOTAL=0; OK=0; MISSING_EV=0; CMD_FAIL=0; SKIPPED=0

# Parse the table: rows begin with "| C-" so the header and prose are skipped.
python3 - "$INDEX" > /tmp/chain_rows.tsv <<'PY'
import sys, re
for line in open(sys.argv[1], encoding='utf-8'):
    if not line.strip().startswith('| C-'):
        continue
    cols = [c.strip() for c in line.strip().strip('|').split('|')]
    if len(cols) < 7:
        continue
    cid, claim, ev, cmd, label, task, verified = cols[:7]
    print('\t'.join([cid, ev, cmd, label, task]))
PY

while IFS=$'\t' read -r CID EV CMD LABEL TASK; do
  [ -z "${CID:-}" ] && continue
  TOTAL=$((TOTAL+1))

  # Evidence artifact present?
  EV_FIRST=$(printf '%s' "$EV" | cut -d, -f1 | tr -d ' ')
  if [ -e "$REPO/$EV_FIRST" ]; then
    EVSTATE="yes"
  else
    EVSTATE="**MISSING**"
    MISSING_EV=$((MISSING_EV+1))
  fi

  if [ "$DRY" = "1" ]; then
    printf '| %s | %s | `%s` | dry, not run |\n' "$CID" "$EVSTATE" "$CMD" >> "$OUT"
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  if [ "$CMD" = "pending" ] || [ "$CMD" = "none, arithmetic" ]; then
    printf '| %s | %s | %s | no command |\n' "$CID" "$EVSTATE" "$CMD" >> "$OUT"
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  # Strip backticks the markdown may carry.
  RUN=$(printf '%s' "$CMD" | tr -d '`')
  if ( cd "$REPO" && eval "$RUN" ) > /tmp/chain_cmd.log 2>&1; then
    printf '| %s | %s | `%s` | PASS |\n' "$CID" "$EVSTATE" "$CMD" >> "$OUT"
    OK=$((OK+1))
  else
    printf '| %s | %s | `%s` | **FAIL** |\n' "$CID" "$EVSTATE" "$CMD" >> "$OUT"
    CMD_FAIL=$((CMD_FAIL+1))
    echo "  [$CID] COMMAND FAILED: $RUN"
    tail -6 /tmp/chain_cmd.log | sed 's/^/      /'
  fi
done < /tmp/chain_rows.tsv

{
  echo
  echo "## Summary"
  echo
  echo "- rows: $TOTAL"
  echo "- commands passed: $OK"
  echo "- commands failed: $CMD_FAIL"
  echo "- evidence artifacts missing: $MISSING_EV"
  echo "- skipped (dry or no command): $SKIPPED"
} >> "$OUT"

echo "rows=$TOTAL pass=$OK fail=$CMD_FAIL missing_evidence=$MISSING_EV skipped=$SKIPPED"
echo "written: $OUT"

# Fail the script when a command fails, so this can gate CI and Phase 10.
if [ "$CMD_FAIL" != "0" ]; then
  echo "CHAIN VERIFICATION FAILED. Per R-EVIDENCE those claims get CUT, not footnoted."
  exit 1
fi
exit 0
