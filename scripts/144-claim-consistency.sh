#!/usr/bin/env bash
# Task 10.3: the measured number appears wherever the claim appears, or the claim is deleted.
#
# THINKING: #60 map-territory, #19 critical thinking.
#
# EVIDENCE PATH: evidence/phase10/claim-consistency.txt
# PASS: the same number in all three places, or the claim is deleted.
#
# THE NUMBER IS DERIVED FROM THE MARKS FILE, not typed here. If a later run changes the median, this
# script reports a mismatch instead of quietly agreeing with a stale figure. That is the whole point:
# a consistency checker that hardcodes the number it is checking is checking nothing.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase10/claim-consistency.txt"
MARKS="$REPO/evidence/phase10/flow-marks.jsonl"
mkdir -p "$(dirname "$OUT")"

MEASURED=$(python3 - "$MARKS" <<'PY'
import collections, json, statistics, sys
runs = collections.defaultdict(dict)
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    runs[d["runId"]][d["mark"]] = d["sinceFirstPaintMs"]
done = [m["activated"] for m in runs.values() if "activated" in m]
print(f"{statistics.median(done) / 1000:.1f}" if done else "NONE")
PY
)

{
echo "Task 10.3, claim consistency"
echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "Measured median, computed from $MARKS: ${MEASURED}s"
echo "This script derives the number rather than hardcoding it, so a stale figure in a document"
echo "produces a mismatch instead of silent agreement."
echo
echo "== where the claim must appear =="
} > "$OUT"

MISSING=0
WRONG=0

check_file() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then
    printf '  %-16s %-44s MISSING FILE\n' "$label" "$path" >> "$OUT"
    MISSING=$((MISSING + 1))
    return
  fi
  # Any timing claim at all in this file.
  local claims
  claims=$(grep -oiE '[0-9]+(\.[0-9])? ?(seconds|s\b)' "$path" | head -5 || true)
  if grep -q "${MEASURED}" "$path" && grep -q "C-1001" "$path"; then
    printf '  %-16s %-44s OK, carries %ss and C-1001\n' "$label" "$path" "$MEASURED" >> "$OUT"
  elif [ -z "$claims" ]; then
    printf '  %-16s %-44s NO CLAIM (acceptable: the claim is absent, not wrong)\n' "$label" "$path" >> "$OUT"
  else
    printf '  %-16s %-44s MISMATCH, found: %s\n' "$label" "$path" "$(echo "$claims" | tr '\n' ' ')" >> "$OUT"
    WRONG=$((WRONG + 1))
  fi
}

check_file "README"      "$REPO/README.md"
# Repo ROOT, not docs/. Phase 10 wrote this path expecting the guide to land in docs/; it lives at
# the root, which is where README links it and where a judge looks first. The gate reported it as a
# missing file for six phases, correctly refusing to call that a pass.
check_file "JUDGE-GUIDE" "$REPO/JUDGE-GUIDE.md"
check_file "landing"     "$REPO/ui-v2/src/components/personal-view.tsx"

{
echo
echo "missing files: $MISSING"
echo "mismatches:    $WRONG"
echo
if [ "$WRONG" -eq 0 ]; then
  echo "GATE: PASS  no document states a timing figure that disagrees with the measurement."
  if [ "$MISSING" -gt 0 ]; then
    echo "NOTE: $MISSING target file(s) do not exist yet. JUDGE-GUIDE.md is created in Phase 17,"
    echo "and this gate is re-run there. A file that does not exist cannot carry a wrong number,"
    echo "but it also cannot carry a right one, so this is not yet a full pass for that document."
  fi
else
  echo "GATE: FAIL  $WRONG document(s) state a timing figure that disagrees with ${MEASURED}s."
fi
} >> "$OUT"

cat "$OUT"
[ "$WRONG" -eq 0 ]
