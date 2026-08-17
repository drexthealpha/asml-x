#!/usr/bin/env bash
# Task 14.6 gate: the learning effect, shown with its sample size.
#
# THINKING: #49 evidence (a learning claim without its sample size is not a claim), #12 design
# thinking, #19 falsifiability.
#
# EVIDENCE PATH: evidence/phase14/learning-effect.md
# PASS: the effect renders in the personal view, EVERY figure carries its sample size, and removing
# the source makes the panel report an error rather than a zero.
#
# THE NAMED FAKE WIN is "a chart trending up". A rising line on ten points is a picture of noise and
# is the most persuasive thing this panel could show while proving the least. The counter is
# structural rather than editorial: the sample count is stored INSIDE the same object as the figure
# it governs, so a component cannot render the number without having been handed the sample too.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase14/learning-effect.md"
M="$REPO/ui-v2/public/data/metrics.json"
LS="$REPO/ui-v2/public/data/learned-state.json"
mkdir -p "$(dirname "$OUT")"

cd "$REPO/ui-v2"
echo "=== typecheck and build ==="
BUILD=$(/home/zulab/.npm-global/bin/pnpm build 2>&1 | tail -3)
echo "$BUILD"
cd "$REPO"

echo
echo "=== 1. every figure carries its sample ==="
PAIRED=$(python3 - "$M" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
le = m.get("learningEffect") or {}
if not le:
    print("NO learningEffect BLOCK"); raise SystemExit(1)

problems = []
for k, v in le.items():
    if "error" in v:
        continue
    if "value" not in v:
        problems.append(f"{k}: neither value nor error")
    if not v.get("source"):
        problems.append(f"{k}: no source string")

# The rate is the figure most likely to be quoted on its own, so it is the one required to carry
# its sample IN THE SAME OBJECT rather than relying on a component to fetch it from elsewhere.
rate = le.get("hitRateBps", {})
if "value" in rate and "samples" not in (rate["value"] or {}):
    problems.append("hitRateBps: no samples alongside the rate")
for c in (le.get("changes", {}).get("value") or []):
    if not c.get("samples"):
        problems.append(f"changes[{c.get('parameter')}]: no sample count")

print("PAIRED" if not problems else "UNPAIRED: " + "; ".join(problems))
raise SystemExit(0 if not problems else 1)
PY
) && PAIR_RC=0 || PAIR_RC=1
echo "$PAIRED"

echo
echo "=== 2. no-data test: remove the source, the panel must ERROR, not show a zero ==="
cp "$LS" "$LS.bak"
rm -f "$LS"
NODATA=$(bash scripts/88-recompute-metrics.sh < /dev/null 2>&1 | grep -A6 "learning effect" | grep -c "ERROR" || true)
mv "$LS.bak" "$LS"
bash scripts/88-recompute-metrics.sh < /dev/null > /dev/null 2>&1
RESTORED=$(python3 -c "
import json; le=json.load(open('$M'))['learningEffect']
print(sum(1 for v in le.values() if 'error' in v))
")
echo "figures reporting ERROR with no source: $NODATA"
echo "figures reporting ERROR after restore:  $RESTORED"

VERDICT=FAIL
if [ "$PAIR_RC" -eq 0 ] && [ "$NODATA" -gt 0 ] && [ "$RESTORED" -eq 0 ] && echo "$BUILD" | grep -q "built in"; then
  VERDICT=PASS
fi

{
echo "# Task 14.6: the learning effect, with its sample size"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **$VERDICT**"
echo
echo "## The named fake win, and the structural counter"
echo
echo "The fake win is **a chart trending up**. A rising line on ten points is a picture of noise, and"
echo "it is the single most persuasive thing this panel could have shown while proving the least."
echo
echo "The counter is structural rather than editorial. The sample count is stored INSIDE the same"
echo "object as the figure it governs, so a component cannot render the number without having been"
echo "handed the sample as well. Making the honest framing the path of least resistance beats relying"
echo "on whoever writes the next component to remember."
echo
echo "Check: $PAIRED"
echo
echo "## What is actually on screen"
echo
echo '```'
python3 - "$M" <<'PY'
import json, sys
le = json.load(open(sys.argv[1], encoding="utf-8"))["learningEffect"]
s = le["samples"]["value"]
print(f"settled outcomes   {s['settled']}")
print(f"dropped as flat    {s['droppedFlat']}   (market did not move; unscoreable, not wrong)")
r = le["hitRateBps"]["value"]
print(f"signal hit rate    {r['value']/100:.1f}%  (n = {r['samples']})")
print()
print("net move, from the defaults it started at:")
for p in le["netMove"]["value"]:
    mark = "" if p["moved"] else "   (unchanged)"
    print(f"  {p['parameter']:24} {p['default']} -> {p['current']}{mark}")
print()
p = le["realizedPnl"]["value"]
print(f"realized PnL       {p['totalMicro']} micro quote over {p['settlements']} settlements")
print(f"                   {p['profitable']} up, {p['losing']} down, {p['flat']} flat")
print(f"                   {p['basis']}")
PY
echo '```'
echo
echo "## Why the NET move is shown above the per-change list"
echo
echo "The learner clamps every step, so the individual moves are small: the change list reads"
echo "\`411 -> 401\` and a reader concludes nothing happened. The net move says momentum weight has"
echo "fallen from its default of 2000 to 391. Same run, two descriptions, and only the second answers"
echo "\"has this learned anything\"."
echo
echo "**A defect was found doing this.** The learner wrote its parameter history on save and silently"
echo "dropped it on load, so the recorded history was only ever the current process's changes. That is"
echo "the same shape as the pending-queue bug fixed earlier, where short runs learned nothing while"
echo "reporting \`settled 0\`. Fixed, with \`parameter_history_survives_a_reload\` pinning it: disabling"
echo "the restore turns that test red and nothing else."
echo
echo "## The direction of the effect is not softened"
echo
echo "The hit rate is **below a coin flip** and the learner responded by cutting the momentum weight"
echo "toward its floor and raising the thin-book penalty eightfold. That is the system working: it"
echo "noticed the signal was not paying and stopped leaning on it. During the sample run the agent"
echo "went on to choose \`hold\` outright. Presenting that as a setback would present a working"
echo "feedback loop as a defect; presenting it as a profit would be a lie."
echo
echo "## The no-data test"
echo
echo "\`learned-state.json\` was removed and the metrics rebuilt:"
echo
echo "| state | figures reporting ERROR |"
echo "|---|---|"
echo "| source removed | $NODATA |"
echo "| source restored | $RESTORED |"
echo
echo "A failed read yields an \`error\` key and **no \`value\` key at all**, so a consumer cannot"
echo "render a number it was never given. Zero and unreadable look identical on screen and mean"
echo "opposite things, which is why the shape enforces it rather than a convention."
echo
echo "## Patterns applied"
echo
echo "\`ui-v2/src/components/learning-effect-panel.tsx\` cites \`orderbook-row.tsx:34\`,"
echo "\`orderbook-panel.tsx:151-153\` and \`orderbook-panel.tsx:121-137\` from evidence/ui-study.md."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/174-learning-effect.sh"
echo '```'
} > "$OUT"

echo
echo "written: $OUT"
echo "VERDICT: $VERDICT"
[ "$VERDICT" = PASS ]
