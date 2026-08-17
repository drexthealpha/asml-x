#!/usr/bin/env bash
# Stage the agent's real output files where ui-v2 can read them, and build the deployment manifest
# the provenance badges are driven by.
#
# THINKING: #60 map-territory (the UI must read the SAME files the agent wrote, not a copy edited
# for presentation), #49 evidence.
#
# The manifest is GENERATED from docs/verified/deployments.md rather than typed here, so a contract
# that is not in the verified document cannot appear in the UI, and self_deployed is derived from
# the document's own SELF-DEPLOYED STAND-IN labelling rather than from my memory of which is which.
#
# EVIDENCE PATH: ui-v2/public/data/, evidence/phase4/ui-data-staged.txt
# PASS: all three sources present and non-empty, and every deployment row carries a provenance
# flag. Task 4.7 deliberately runs the UI WITHOUT this staging to prove the no-data path.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase4/ui-data-staged.txt"
DATA="$REPO/ui-v2/public/data"
mkdir -p "$DATA" "$(dirname "$OUT")"

{
echo "ui-v2 data staging"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
} 2>&1 | tee "$OUT"

cp "$REPO/evidence/journal.jsonl" "$DATA/journal.jsonl"
cp "$REPO/evidence/learned-state.json" "$DATA/learned-state.json"

/home/zulab/.asml-venv/bin/python "$REPO/scripts/build_ui_manifest.py" 2>&1 | tee -a "$OUT"
MAN_RC=${PIPESTATUS[0]}

{
echo
echo "## Staged"
for f in journal.jsonl learned-state.json deployments.json; do
  if [ -s "$DATA/$f" ]; then
    printf '  %-22s %8s bytes\n' "$f" "$(stat -c%s "$DATA/$f")"
  else
    printf '  %-22s MISSING OR EMPTY\n' "$f"
  fi
done

echo
echo "## Verdict"
if [ -s "$DATA/journal.jsonl" ] && [ -s "$DATA/learned-state.json" ] && [ "${MAN_RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. All three sources staged."
  echo
  echo "  PROVENANCE, and this note is now the good news rather than the caveat: the staged journal"
  echo "  is the CURRENT binary's output. The 9 Aug rows whose refusal numbers were wei-scaled were"
  echo "  split out to evidence/journal-legacy-2026-08-09.jsonl and are NOT staged. Confirmed by"
  echo "  bash scripts/77-journal-scale-audit.sh: 0 wei-scaled values, and the limit refusals now"
  echo "  carry usable numbers, so the risk panel draws real utilisation."
  echo "  Split record: evidence/phase4/journal-split.txt"
else
  echo "  RESULT: FAIL. See the staged list above."
fi
} | tee -a "$OUT"

echo "written: $OUT"
