#!/usr/bin/env bash
# Record C-1406 (task 14.6) into the evidence chain.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN="$REPO/evidence/CHAIN-OF-EVIDENCE.md"

for f in evidence/phase14/learning-effect.md \
         ui-v2/src/components/learning-effect-panel.tsx \
         ui-v2/public/data/metrics.json; do
  if [ ! -s "$REPO/$f" ]; then echo "MISSING OR EMPTY: $f"; exit 1; fi
done

if ! grep -q "Verdict: \*\*PASS\*\*" "$REPO/evidence/phase14/learning-effect.md"; then
  echo "The gate did not pass. Refusing to record."
  exit 1
fi

if grep -q "C-1406" "$CHAIN"; then echo "already recorded"; exit 0; fi
TODAY=$(date -u '+%Y-%m-%d')

cat >> "$CHAIN" <<EOF
| C-1406 | The learning effect is on the landing surface with its sample size attached to every figure, enforced by the SHAPE of the data rather than by editorial care: the sample count lives inside the same object as the figure it governs, so a component cannot render the number without having been handed the sample. Measured: 10 settled outcomes, 36 dropped as flat because the market did not move, a 40.0 percent hit rate that is BELOW a coin flip, and a net parameter move of momentum_weight_bps 2000 to 391 with thin_book_penalty_bps 150 to 1225. The direction is not softened, because a learner that noticed its signal was not paying and cut its weight toward the floor is the system working, and during the sample run the agent went on to choose hold outright. The named fake win, a chart trending up, is refused: a rising line on ten points is a picture of noise. Removing learned-state.json makes 4 figures report ERROR with NO value key and 0 after restore, so a failed read can never be mistaken for a zero | evidence/phase14/learning-effect.md, ui-v2/src/components/learning-effect-panel.tsx | bash scripts/174-learning-effect.sh | DEMONSTRATED | 14.6 | $TODAY |
| C-1407 | A defect found by building 14.6 and FIXED rather than documented: the learner wrote its parameter history on save and silently dropped it on load, so the recorded history was only ever the current process's changes. The panel therefore showed momentum weight moving 411 to 401 when it had in fact fallen from its default of 2000, understating the learning effect by two orders of magnitude while looking entirely plausible. Same shape as the pending-queue defect fixed earlier, where a sequence of short runs learned nothing while reporting settled 0. The regression test parameter_history_survives_a_reload pins it and is shown able to fail: disabling the restore turns exactly that one test red out of 24, and restoring returns all 24 green. The UI additionally shows the NET move against the crate defaults, because the learner clamps each step and a reader seeing only clamped steps concludes nothing happened | crates/learning/src/lib.rs, crates/learning/src/tests.rs, evidence/phase14/learning-effect.md | cargo test -p learning | DEMONSTRATED | 14.6 | $TODAY |
EOF

echo "appended C-1406, C-1407"
grep -c "^| C-" "$CHAIN"
