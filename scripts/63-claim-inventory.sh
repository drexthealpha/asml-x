#!/usr/bin/env bash
# Task 2.1 claim inventory. Extract every factual assertion from every judge-facing document
# and give each one an id, so 2.6 can delete the ones that do not reproduce.
#
# THINKING: #49 skeptical (assume every claim is unsupported until traced to an artifact),
# #60 map-territory (the docs are the map; the evidence directory is the territory; this task
# measures the gap), #19 critical thinking.
#
# EVIDENCE PATH declared before code: evidence/phase2/claim-inventory.txt
# PASS: every extracted assertion carries an id. The fake win named in TASKS.md is writing the
# index from memory of what v1 claimed, so nothing here is typed from memory: the extractor
# reads the files and every row carries the file and line it came from.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase2/claim-inventory.txt"
CSV="$REPO/evidence/phase2/claim-inventory.csv"
mkdir -p "$(dirname "$OUT")"

{
echo "Claim inventory, task 2.1"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Scope: every judge-facing document"
} 2>&1 | tee "$OUT"

cd "$REPO"
/home/zulab/.asml-venv/bin/python scripts/claim_inventory.py 2>&1 | tee -a "$OUT"
RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict, task 2.1"
if [ "${RC:-1}" -eq 0 ] && [ -f "$CSV" ]; then
  echo "  RESULT: PASS. $(($(wc -l < "$CSV") - 1)) assertions extracted, each with an id and a"
  echo "  file:line origin. Machine-readable copy: evidence/phase2/claim-inventory.csv"
  echo "  Nothing here was typed from memory; every row cites where it was read from."
else
  echo "  RESULT: FAIL, exit $RC."
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit "${RC:-1}"
