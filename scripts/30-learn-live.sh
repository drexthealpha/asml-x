#!/usr/bin/env bash
# Phase 7 live proof: the learning loop against real chain state.
#
# Two runs, deliberately:
#   1. cold: learned state deleted, so the first run starts from default params
#   2. warm: the same binary resumed from the persisted state
# The difference between them is the evidence that learning persists and matters.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$PATH"

EVID="$REPO/evidence/learning"
mkdir -p "$EVID"
STATE="$REPO/evidence/learned-state.json"
CYCLES="${1:-14}"

cd "$REPO"
cargo build --release -p runtime 2>&1 | tail -1

echo "=================================================================="
echo "COLD START: removing persisted learned state"
echo "=================================================================="
rm -f "$STATE"
ASML_REPO="$REPO" ./target/release/asml learn "$CYCLES" 2>&1 | tee "$EVID/cold-run.txt"

echo
echo "=================================================================="
echo "PERSISTED STATE AFTER THE COLD RUN"
echo "=================================================================="
python3 -c "
import json
d = json.load(open('$STATE'))
print('params     ', json.dumps(d['params']))
print('settled    ', d['settled_count'])
print('stats      ', json.dumps(d['stats']))
print('changes    ', len(d['history']))
for c in d['history']:
    print('   ', c['parameter'], c['from'], '->', c['to'], '|', c['trigger'])
" | tee "$EVID/state-after-cold.txt"

echo
echo "=================================================================="
echo "WARM RESUME: same binary, state NOT deleted"
echo "=================================================================="
ASML_REPO="$REPO" ./target/release/asml learn 6 2>&1 | tee "$EVID/warm-run.txt"

echo
echo "=================================================================="
echo "COLD versus WARM"
echo "=================================================================="
{
  echo "cold run started from default params:"
  grep -m1 "params at start" "$EVID/cold-run.txt" || true
  echo "cold run settled-so-far at start:"
  grep -m1 "settled so far" "$EVID/cold-run.txt" || true
  echo
  echo "warm run started from LEARNED params:"
  grep -m1 "params at start" "$EVID/warm-run.txt" || true
  echo "warm run settled-so-far at start:"
  grep -m1 "settled so far" "$EVID/warm-run.txt" || true
  echo
  echo "If the two 'params at start' lines differ, learned state survived the restart"
  echo "and was actually loaded, which is the whole claim."
} | tee "$EVID/cold-vs-warm.txt"

echo
echo "written: $EVID/"
