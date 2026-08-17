#!/usr/bin/env bash
# Task 5.7 Phase 5 adversarial audit.
#
# THINKING: #66 red teaming (attack the UI's central claim, not its edges), #7 counterfactual (if the
# agent were a hardcoded rule, what would its journal look like, and would this UI say so?).
#
# THE ATTACK: a journal where every cycle scored exactly ONE candidate. That is what an if-else ladder
# produces: an action with a score attached after the fact. The brain panel's whole argument is "look
# at the candidates it rejected", so a UI that renders a one-candidate cycle in the same style as a
# 53-candidate one is vouching for reasoning it cannot see.
#
# A second, harsher fixture: cycles with ZERO candidates, an action recorded with no reasoning at all.
#
# EVIDENCE PATH declared before code: evidence/phase5/phase5-redteam.md
# PASS: single-candidate cycles are visibly flagged as defects.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase5/phase5-redteam.md"
mkdir -p "$(dirname "$OUT")"
RT="/home/zulab/redteam5"

rm -rf "$RT"
mkdir -p "$RT/data"
cp -r "$REPO/ui-v2/dist/." "$RT/"
for f in learned-state.json deployments.json metrics.json comparator.json; do
  cp "$REPO/ui-v2/public/data/$f" "$RT/data/" 2>/dev/null || true
done

/home/zulab/.asml-venv/bin/python - <<'PY'
import json

SRC = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/ui-v2/public/data/journal.jsonl"
DST = "/home/zulab/redteam5/data/journal.jsonl"

rows = [json.loads(l) for l in open(SRC, encoding="utf-8") if l.strip()]
out = []
for i, r in enumerate(rows):
    c = dict(r)
    cands = r.get("candidates") or []
    # Alternate the two attacks so both appear in one fixture: most rows keep exactly the chosen
    # candidate, and every fifth row keeps none at all.
    if i % 5 == 4:
        c["candidates"] = []
    else:
        chosen = [x for x in cands if x.get("chosen")] or cands[:1]
        c["candidates"] = chosen[:1]
    out.append(c)

with open(DST, "w", encoding="utf-8", newline="\n") as fh:
    for r in out:
        fh.write(json.dumps(r) + "\n")

one = sum(1 for r in out if len(r["candidates"]) == 1)
zero = sum(1 for r in out if len(r["candidates"]) == 0)
print(f"  fixture rows: {len(out)}  single-candidate: {one}  zero-candidate: {zero}")
PY

echo "  serving the fixture at http://localhost:4177"
pkill -f "http.server 4177" 2>/dev/null || true
sleep 1
cd "$RT" && nohup /home/zulab/.asml-venv/bin/python -m http.server 4177 --bind 0.0.0.0 \
  > /home/zulab/serve-4177.log 2>&1 &
sleep 2
printf '  HTTP %s\n' "$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:4177/index.html)"
echo
echo "  Now open http://localhost:4177 and run the assertion in scripts/measure-redteam5.js"
