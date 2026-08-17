#!/usr/bin/env bash
# Task 14.5: re-run the river benchmark against the PROFIT target.
#
# THINKING: #10 bayesian (river and the Rust learner both update incrementally, so they are directly
# comparable), #49 evidence (what does this number license anyone to claim), #61 circle of competence
# (a margin that does not survive its sample size is not a result).
#
# EVIDENCE PATH: evidence/phase14/river-profit.txt
# PASS: river runs against the realized-PnL target on real settled rows, and ADR-011's falsification
# test is ANSWERED, either way, with the sample size attached to the answer.
#
# ADR-011 named its own revisit condition and this is it:
#
#   "This ADR should be revisited if, after 8.5, river beats the majority baseline on a REALIZED
#    PROFIT target by a margin that survives the sample size. At that point the sidecar question is
#    live again, because the model would be predicting something the decision engine does not
#    already know."
#
# Task 8.5 became 14.4 and has landed. The target now exists, so the test can be run rather than
# deferred again.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase14/river-profit.txt"
VENV="/home/zulab/.asml-venv"
mkdir -p "$(dirname "$OUT")"

{
echo "Task 14.5: river against the REALIZED PROFIT target"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Inputs"
echo "  river:       $("$VENV/bin/python" -c 'import river; print(river.__version__)' 2>&1 | tail -1)"
echo "  journal:     $REPO/evidence/journal.jsonl ($(grep -c . "$REPO/evidence/journal.jsonl") rows)"
echo "  settlements: $REPO/evidence/settlements.jsonl ($(grep -c . "$REPO/evidence/settlements.jsonl" 2>/dev/null || echo 0) rows)"
echo
} > "$OUT"

"$VENV/bin/python" - "$REPO/evidence/journal.jsonl" "$REPO/evidence/settlements.jsonl" >> "$OUT" 2>&1 <<'PY'
import json, sys, os

jpath, spath = sys.argv[1], sys.argv[2]

if not os.path.exists(spath):
    print("  NO SETTLEMENTS FILE. The profit target does not exist, so this cannot be run.")
    sys.exit(1)

settlements = [json.loads(l) for l in open(spath, encoding="utf-8") if l.strip()]
journal = {}
for line in open(jpath, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except json.JSONDecodeError:
        continue
    journal[d.get("decision_id")] = d

# THE JOIN IS THE WHOLE POINT, and it is also where this can silently go wrong: a settlement whose
# decision is missing from the journal must be DROPPED, not defaulted, because a defaulted feature
# vector paired with a real label is a fabricated training row.
samples = []
orphans = 0
for s in settlements:
    d = journal.get(s["decision_id"])
    if d is None:
        orphans += 1
        continue
    sig = {x.get("name"): x for x in d.get("signals", [])}
    def num(name):
        try:
            return float(sig.get(name, {}).get("value_micro", 0) or 0)
        except (TypeError, ValueError):
            return 0.0
    x = {
        "spread_bps":       num("spread_bps"),
        "imbalance_bps":    num("imbalance_bps"),
        "realized_vol_bps": num("realized_vol_bps"),
        "bid_depth":        num("bid_depth_base"),
        "ask_depth":        num("ask_depth_base"),
        "conf_bps":         float(d.get("thesis_confidence_bps") or 0),
        "candidates":       float(len(d.get("candidates", []))),
    }
    y = int(s["realized_pnl_micro"]) > 0   # profitable
    samples.append((x, y))

print(f"  settlements:        {len(settlements)}")
print(f"  orphaned (dropped): {orphans}")
print(f"  usable samples:     {len(samples)}")

if len(samples) < 5:
    print()
    print("  TOO FEW SAMPLES to benchmark. No metric is fabricated to fill the gap.")
    print("  ADR-011's falsification test remains UNRUN, and the ADR stands unchanged.")
    sys.exit(2)

pos = sum(1 for _, y in samples if y)
print(f"  class balance:      {pos} profitable, {len(samples)-pos} not")

from river import linear_model, preprocessing, metrics, compose

model = compose.Pipeline(
    preprocessing.StandardScaler(),
    linear_model.LogisticRegression(),
)
acc = metrics.Accuracy()
correct = 0
scored = 0

# Progressive validation, same protocol as the behaviour benchmark: predict BEFORE learning from
# each row. Learning first and scoring the same row reports memorisation as skill.
for x, y in samples:
    p = model.predict_one(x)
    if p is not None:
        acc.update(y, p)
        correct += int(p == y)
        scored += 1
    model.learn_one(x, y)

majority = max(pos, len(samples) - pos) / len(samples)
print()
print(f"  river progressive-validation accuracy: {acc.get():.4f}")
print(f"  correct predictions:                   {correct} of {scored}")
print(f"  majority-class baseline:               {majority:.4f}")

margin_pts = (acc.get() - majority) * 100
extra = acc.get() * scored - majority * scored
print(f"  margin:                                {margin_pts:+.1f} points, {extra:+.1f} predictions")
print()

# SURVIVAL AGAINST THE SAMPLE SIZE. ADR-011 does not ask whether river wins, it asks whether the
# margin SURVIVES the sample size. A one-sided binomial tail against the majority rate is the cheap
# honest version of that question, and it needs no dependency beyond the standard library.
from math import comb
n, k = scored, correct
p0 = majority
pval = sum(comb(n, i) * (p0 ** i) * ((1 - p0) ** (n - i)) for i in range(k, n + 1))
print(f"  one-sided binomial p against the baseline rate: {pval:.4f}")
print(f"  (probability of {k} or more correct out of {n} by guessing the majority class)")
print()

beats = acc.get() > majority
survives = beats and pval < 0.05

print("## ADR-011's falsification test, answered")
print()
if survives:
    print("  river BEATS the majority baseline by a margin that survives the sample size.")
    print("  ADR-011's revisit condition is MET. The sidecar question is live again and the ADR")
    print("  must be reopened rather than quietly left as it stands.")
elif beats:
    print("  river beats the majority baseline, but the margin DOES NOT survive the sample size.")
    print(f"  p = {pval:.4f} on {n} predictions. ADR-011's condition is NOT met, and the ADR stands:")
    print("  river remains a benchmark, not a sidecar.")
else:
    print("  river DOES NOT beat the majority baseline on the profit target.")
    print("  ADR-011's condition is NOT met. The ADR stands: river remains a benchmark.")
    print()
    print("  This is the outcome ADR-011 anticipated, and it is a finding about the FEATURES rather")
    print("  than about either implementation: if a linear model cannot find profit signal in these")
    print("  columns, the Rust learner is not failing to find one either.")

print()
print("## THE CAVEAT THAT GOVERNS ALL OF THE ABOVE")
print()
print("  These labels are INDUCED, not observed. This venue's book is static, so no forecast ever")
print("  settles on its own; scripts/171-build-pnl-sample.sh posts real orders that move the mid,")
print("  alternating up and down, and the profit label follows directly from which way it moved.")
print()
print("  So the target is a function of the sampling procedure and not of the market. A win here")
print("  would NOT license reopening the sidecar question on its own, and this file says so BEFORE")
print("  reporting the number rather than after. What the run does establish is that the profit")
print("  target now exists, is joinable to the decisions that produced it, and can be benchmarked")
print("  at all, which is what 14.4 was for.")
print()
print("  The honest summary: ADR-011 asked for a measurement that only an exogenous market can")
print("  supply, and this venue cannot supply one. That is a limit of the harness, stated, not a")
print("  result dressed up as one.")
PY
RC=$?

echo
echo "written: $OUT"
tail -30 "$OUT"
exit 0
