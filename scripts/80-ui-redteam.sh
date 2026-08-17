#!/usr/bin/env bash
# Task 4.9 Phase 4 adversarial audit. Try to make the UI display a number that is not in the
# journal, and feed it malformed input.
#
# THINKING: #66 red teaming (attack my own artifact, and the attacks have to be ones that would
# actually fool a reader), #7 counterfactual (for each attack, what would the UI have to do wrong
# for it to succeed), #60 falsifiability.
#
# PASS: every malformed input produces a visible error state, never a plausible number. The failure
# mode being hunted is a UI that silently coerces bad data into something believable, which is
# strictly worse than crashing.
#
# EVIDENCE PATH declared before code: evidence/phase4/phase4-redteam.md plus the served fixtures
# under /home/zulab/redteam-check for a human to click through.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase4/redteam-fixtures.txt"
mkdir -p "$(dirname "$OUT")"
RT="/home/zulab/redteam-check"

rm -rf "$RT"
mkdir -p "$RT/data"
cp -r "$REPO/ui-v2/dist/." "$RT/"

{
echo "Phase 4 red-team fixtures"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Attacks staged, each one a way a dashboard usually lies"
} 2>&1 | tee "$OUT"

# ATTACK 1: a truncated JSON line. The classic tail-of-file case when a writer is interrupted.
# ATTACK 2: valid JSON, wrong types. Strings where numbers belong, a null where an array belongs.
# ATTACK 3: a row with no decision_id. Valid JSON, unusable as a decision.
# ATTACK 4: a row whose numbers are absurd, to see whether the UI renders them as if fine.
# ATTACK 5: one GOOD row at the end, so the panel has something to show. This is the important
#           part of the fixture: if bad rows were simply dropped and the good one rendered with no
#           indication, the UI would be hiding data loss behind a plausible screen.
cat > "$RT/data/journal.jsonl" <<'JSONL'
{"decision_id":1,"block_number":1,"action":"hold","thesis":"truncated next
{"decision_id":"not-a-number","block_number":{"nested":true},"action":42,"signals":null,"candidates":"nope","evidence":7,"thesis_confidence_bps":"NaN"}
{"block_number":9,"action":"take order 1 Buy","thesis":"no decision id at all","candidates":[],"signals":[]}
{"decision_id":4,"block_number":99999999999999999999,"action":"take order 9 Buy 1e30 base","thesis":"absurd magnitudes","thesis_confidence_bps":999999999,"signals":[{"name":"spread_bps","value_micro":"999999999999999999999999999999","confidence_halfwidth_micro":"0","input_age_ms":0}],"candidates":[{"label":"take absurd","chosen":true,"score_micro":"999999999999999999999999999999","expected_edge_micro":"0","variance_penalty_micro":"0","capital_cost_micro":"0","execution_risk_penalty_micro":"0","rejection_reason":null}],"evidence":["fabricated"]}
{"decision_id":5,"block_number":38000000,"action":"hold","thesis":"the one good row","thesis_confidence_bps":5000,"risk_verdict":"hold outscored every permitted action","signals":[{"name":"spread_bps","value_micro":"512","confidence_halfwidth_micro":"102","input_age_ms":0}],"candidates":[{"label":"hold","chosen":true,"score_micro":"0","expected_edge_micro":"0","variance_penalty_micro":"0","capital_cost_micro":"0","execution_risk_penalty_micro":"0","rejection_reason":null}],"evidence":["eth_call venue.orderCount at block 38000000"],"tx_hash":null}
JSONL

# ATTACK 6: learned-state.json that is not JSON at all.
printf '{"settled_count": 2, "stats": {broken\n' > "$RT/data/learned-state.json"

# ATTACK 7: deployments.json served as HTML, the shape a dev server returns for a missing file.
printf '<!doctype html><html><body>not json</body></html>\n' > "$RT/data/deployments.json"

{
echo "  1. truncated JSON line"
echo "  2. valid JSON with every field the wrong type"
echo "  3. a row with no decision_id"
echo "  4. absurd magnitudes: 1e30 score, 999999999 bps confidence, a 20-digit block number"
echo "  5. one GOOD row, so a silent drop of the bad ones would look like a working screen"
echo "  6. learned-state.json that is not JSON"
echo "  7. deployments.json served as HTML, which is what a dev server returns for a missing file"
echo
echo "## Serve"
echo "  cd $RT && python3 -m http.server 4175 --bind 127.0.0.1"
echo "  then open http://127.0.0.1:4175/"
echo
echo "  journal lines: $(wc -l < "$RT/data/journal.jsonl")"
echo "  fixtures at:   $RT/data"
} | tee -a "$OUT"

echo "written: $OUT"
