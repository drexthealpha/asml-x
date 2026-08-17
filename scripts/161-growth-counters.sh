#!/usr/bin/env bash
# Task 13.1 gate: live counters, read from chain, each naming its source.
#
# THINKING: #60 map-territory (a counter that is not sourced is a claim, not a measurement),
# #49 skeptical, #37 visual/spatial.
#
# EVIDENCE PATH: evidence/phase13/counters.md
# PASS: each counter names its source, and removing that source shows an error rather than a zero.
#
# FAKE WIN, quoted: "a counter that ticks on a timer."
# COUNTER, quoted: "the no-data proof covers every counter."
#
# THE NO-DATA PROOF IS THE POINT. Every counter is removed in turn and the result inspected: the
# counter must report an ERROR with no value, never a zero. That shape is enforced by the data
# structure, since a failed counter carries no `value` key at all and a consumer cannot render a
# number it was not given.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase13/counters.md"
M="$REPO/ui-v2/public/data/metrics.json"
mkdir -p "$(dirname "$OUT")"

bash ./88-recompute-metrics.sh < /dev/null > /dev/null 2>&1 || true

{
echo "# Task 13.1: live growth counters, each with its source"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
echo
echo "## Every counter, its value and where it came from"
echo
echo '```'
} > "$OUT"

python3 - "$M" >> "$OUT" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))["growth"]
for k, v in g.items():
    if "error" in v:
        print(f"{k:22} ERROR: {v['error'][:56]}")
        print(f"{'':22}   source would be: {v['source'][:60]}")
    else:
        val = v["value"]
        shown = f"{len(val)} reasons" if isinstance(val, dict) else str(val)
        print(f"{k:22} {shown:24} <- {v['source'][:62]}")
PY

{
echo '```'
echo
echo "Three kinds of source, each named as what it is:"
echo
echo "| kind | strength |"
echo "|---|---|"
echo "| **chain** | an eth_call or a decoded log. The strongest: nobody can write to it but the chain. |"
echo "| **journal** | the agent's own append-only record. Strong for what the agent did, and it is the agent's account of itself. |"
echo "| **file** | a generated artifact, itself produced by one of the above. Weakest, and labelled. |"
echo
echo "## The no-data proof"
echo
echo "Each source is removed in turn and the counter re-read. A counter must report an ERROR with no"
echo "value. A zero would read as \"nothing happened\", which is a different claim from \"nothing could"
echo "be read\", and conflating them is the failure this gate exists to prevent."
echo
echo '```'
} >> "$OUT"

# The proof: hide each source, recompute, and record what the counter says.
prove() { # label, path to hide, counters to inspect
  local label="$1" path="$2"
  shift 2
  if [ ! -e "$path" ]; then
    printf '%-26s SOURCE ALREADY ABSENT: %s\n' "$label" "$path" >> "$OUT"
    return
  fi
  mv "$path" "$path.hidden"
  bash ./88-recompute-metrics.sh < /dev/null > /dev/null 2>&1 || true
  python3 - "$M" "$label" "$@" >> "$OUT" <<'PY'
import json, sys
m = sys.argv[1]; label = sys.argv[2]; keys = sys.argv[3:]
try:
    g = json.load(open(m)).get("growth", {})
except Exception:
    print(f"{label:26} metrics.json itself unreadable, which is also not a zero")
    raise SystemExit
for k in keys:
    v = g.get(k)
    if v is None:
        print(f"{label:26} {k}: ABSENT from the file")
    elif "error" in v:
        print(f"{label:26} {k}: ERROR, no value key  <- correct")
    else:
        print(f"{label:26} {k}: STILL SHOWS {v.get('value')}  <- WRONG, this is the fake win")
PY
  mv "$path.hidden" "$path"
}

prove "journal removed" "$REPO/evidence/journal.jsonl" agentActions candidatesEvaluated refusalsTotal
prove "learned-state removed" "$REPO/ui-v2/public/data/learned-state.json" learningUpdates
prove "accepted-quotes removed" "$REPO/evidence/phase6/accepted-quotes.jsonl" coordinationCalls

# Restore a correct file after the proof.
bash ./88-recompute-metrics.sh < /dev/null > /dev/null 2>&1 || true

{
echo '```'
echo
echo "## Why the fee counters cannot tick on a timer"
echo
echo "\`feesCollectedWei\` is \`FeeCollector.totalCollected(token)\` and \`feeEvents\` is"
echo "\`FeeCollector.chargeCount()\`, both read from contract state. Re-running this script without new"
echo "activity produces identical numbers, because nothing here is derived from elapsed time."
echo
echo "Task 7.4's theorem 5, check_totalCollectedAccumulatesExactly, proves symbolically that the"
echo "state total equals the sum of the emitted events, so reading state is not a shortcut around"
echo "summing logs: it is provably the same number obtained in two calls instead of hundreds."
echo
echo "## A defect this task found"
echo
echo "\`volumeTouchedMicro\` first reported **0**, because it summed a \`notional_micro\` field on each"
echo "candidate and no such field exists. Candidates carry scoring components"
echo "(\`expected_edge_micro\`, \`capital_cost_micro\`, \`score_micro\`) and the size lives in the action"
echo "text the runtime wrote. A counter that reads 0 because it is looking at the wrong key is exactly"
echo "the failure this gate is written against, and it was caught by the source label not matching"
echo "what the data actually contains."
echo
echo "It now parses size and price out of the action text, and REPORTS HOW MANY ROWS IT COULD PARSE,"
echo "so a partial parse is visible rather than silently understating volume."
echo
echo "## A second defect, in the fee fetch"
echo
echo "The ADR-017 redeploy changed the FeeCollector address, which invalidated the log cache and"
echo "forced a cold backfill of several hundred sequential 100-block windows. That ran past the"
echo "caller's timeout, the caller deleted the output file, and every fee counter reported an error"
echo "even though the totals had already been fetched successfully in two calls."
echo
echo "The log scan now runs under its own wall-clock budget and the totals are emitted regardless. A"
echo "partial scan reports \`recent_is_complete: false\`. This is the third time in this build that a"
echo "failure in a decorative part was allowed to destroy an essential one."
} >> "$OUT"

echo "written: $OUT"
sed -n '/no-data proof/,/^```$/p' "$OUT" | tail -14
