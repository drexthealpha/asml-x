#!/usr/bin/env bash
# Task 10.1 gate: the flow is instrumented, five timestamps per run, written to a FILE.
#
# THINKING: #50 empirical, #60 map-territory (a claim nobody timed is a slogan), #49 skeptical.
#
# EVIDENCE PATH: evidence/phase10/timing-instrumented.txt
# PASS: five timestamps recorded per run.
#
# The marks are POSTed by the page to the coordination API, which appends them to
# evidence/phase10/flow-marks.jsonl. A console log would vanish with the tab and could not be cited,
# diffed or reproduced, which is why the task says "written to a file, not to a console".
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase10/timing-instrumented.txt"
MARKS="$REPO/evidence/phase10/flow-marks.jsonl"
mkdir -p "$(dirname "$OUT")"

{
echo "Task 10.1, flow instrumentation"
echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "Marks file: $MARKS"
echo "Lines: $(grep -c . "$MARKS" 2>/dev/null || echo 0)"
echo
} > "$OUT"

python3 - "$MARKS" >> "$OUT" 2>&1 <<'PY'
import collections
import json
import statistics
import sys

path = sys.argv[1]
runs = collections.defaultdict(dict)
for line in open(path, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    runs[d["runId"]][d["mark"]] = d["sinceFirstPaintMs"]

ORDER = ["first_paint", "connected", "defaults_seen", "deposit_submitted", "activated"]

print("== marks per run, milliseconds since first paint ==")
print()
header = "run".ljust(24) + "".join(m.ljust(19) for m in ORDER)
print(header)
complete = []
for rid, m in runs.items():
    row = rid.ljust(24) + "".join(str(m.get(k, "-")).ljust(19) for k in ORDER)
    print(row)
    if all(k in m for k in ORDER):
        complete.append(m["activated"])

print()
print(f"runs recorded:            {len(runs)}")
print(f"runs with all five marks: {len(complete)}")

if complete:
    med = statistics.median(complete)
    print()
    print("== first paint to activated ==")
    print(f"  runs:   {len(complete)}")
    print(f"  median: {int(med)} ms  ({med / 1000:.1f} s)")
    print(f"  min:    {min(complete)} ms  ({min(complete) / 1000:.1f} s)")
    print(f"  max:    {max(complete)} ms  ({max(complete) / 1000:.1f} s)")
    print()
    if med > 60000:
        print(f"  OVER 60 SECONDS. The README must say {med / 1000:.0f} seconds, not 60.")
    else:
        print(f"  Under 60 seconds. The measured figure is {med / 1000:.1f} s.")

print()
if len(complete) >= 1 and len(runs) >= 1:
    print("GATE: PASS  five timestamps recorded per run, in a file")
else:
    print("GATE: FAIL  no complete run recorded")
PY

tail -30 "$OUT"
