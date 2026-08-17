#!/usr/bin/env bash
# Task 5.3 load fixture: 500+ journal entries, to check the windowed feed scrolls without jank.
#
# THINKING: #50 empirical (measure mounted node counts and frame cost, do not assert smoothness),
# #66 red teaming (the way virtualisation fails is by mounting everything anyway, so count the
# mounted rows), #29 margin-of-safety.
#
# HONEST LABELLING, and this matters: the rows in this fixture are SYNTHETIC, produced by repeating
# the real journal with shifted ids and blocks. They exist to load the renderer, never to be shown
# as product data. They are served from a separate directory (/home/zulab/loadtest-check) and are
# NOT staged into ui-v2/public/data, so no screenshot of the product can contain them. Task 4.7's
# no-data proof and this load test are the two places where the UI is deliberately fed something
# other than the agent's real output, and both say so.
#
# EVIDENCE PATH declared before code: evidence/phase5/journal-load-test.txt
# PASS: 500+ entries scroll with only a window of rows mounted.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase5/journal-load-test.txt"
mkdir -p "$(dirname "$OUT")"
LT="/home/zulab/loadtest-check"

rm -rf "$LT"
mkdir -p "$LT/data"
cp -r "$REPO/ui-v2/dist/." "$LT/"
cp "$REPO/ui-v2/public/data/learned-state.json" "$LT/data/"
cp "$REPO/ui-v2/public/data/deployments.json" "$LT/data/"
cp "$REPO/ui-v2/public/data/metrics.json" "$LT/data/" 2>/dev/null || true

{
echo "Journal load test, task 5.3"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Fixture"
echo "  SYNTHETIC rows, built by repeating the real journal with shifted decision ids and block"
echo "  numbers. Served only from $LT, never staged into ui-v2/public/data, so the product build"
echo "  cannot show them."
} 2>&1 | tee "$OUT"

/home/zulab/.asml-venv/bin/python - <<'PY' 2>&1 | tee -a "$OUT"
import json

SRC = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/ui-v2/public/data/journal.jsonl"
DST = "/home/zulab/loadtest-check/data/journal.jsonl"
TARGET = 600

rows = [json.loads(l) for l in open(SRC, encoding="utf-8") if l.strip()]
out = []
i = 0
while len(out) < TARGET:
    for r in rows:
        c = dict(r)
        i += 1
        c["decision_id"] = str(10_000 + i)
        c["block_number"] = str(int(r["block_number"]) + i)
        # Trim the candidate list to 6 per row. The first fixture kept all 53 and came to 9.5 MB,
        # which tripped the loader's own 4 MB read limit in lib/data.ts. Raising that limit to make a
        # load test pass would weaken a real protection to accommodate a test, which is backwards.
        # This test is about ROW COUNT and mounted-node count, so the candidate depth is irrelevant
        # to it and the guard stays as it is.
        c["candidates"] = (r.get("candidates") or [])[:6]
        # Marked in the action text so a human looking at the load fixture cannot mistake it for
        # product data even if they arrive at the page without reading this script.
        c["action"] = f"[SYNTHETIC LOAD FIXTURE] {r.get('action', '')}"
        out.append(c)
        if len(out) >= TARGET:
            break

with open(DST, "w", encoding="utf-8", newline="\n") as fh:
    for r in out:
        fh.write(json.dumps(r) + "\n")

print(f"  source rows: {len(rows)}")
print(f"  fixture rows written: {len(out)}")
print(f"  bytes: {__import__('os').path.getsize(DST)}")
PY

{
echo
echo "## Serve"
echo "  cd $LT && python3 -m http.server 4176 --bind 127.0.0.1"
echo "  then open http://127.0.0.1:4176/ and run the measurement in scripts/measure-feed.js"
echo
echo "## What to look for"
echo "  MOUNTED ROWS must stay near the window size (visible + 2 x OVERSCAN, so roughly 36 to 56"
echo "  for a panel of this height), NOT 600. A virtualised list that mounts everything is a"
echo "  virtualised list in name only, and the mounted count is the only honest way to tell."
} | tee -a "$OUT"

echo "written: $OUT"
