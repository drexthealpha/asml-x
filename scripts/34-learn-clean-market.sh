#!/usr/bin/env bash
# Phase 7 live proof, decisive version.
#
# Why the previous attempts scored nothing: postOrder ADDS to the book and never removes
# anything, so old low asks pinned best_ask down and the mid barely moved no matter what
# new levels were posted. The fix is one line of behaviour, not an investigation: CANCEL
# every live order before posting the next level, so the book holds exactly one bid and
# one ask and the mid is whatever the simulator says it is.
#
# Counterparty flow is SIMULATED, and labelled as such: chain 1952 has no other
# participants. The orders, cancels, fills and price path are all real onchain state.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$PATH"

EVID="$REPO/evidence/learning"
mkdir -p "$EVID"
STATE="$REPO/evidence/learned-state.json"
RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
BASE=$(python3 -c "import json;print(json.load(open('$J'))['tBASE'])")
QUOTE=$(python3 -c "import json;print(json.load(open('$J'))['tQUOTE'])")
VENUE=$(python3 -c "import json;print(json.load(open('$J'))['venue'])")

send_q() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" \
    >/dev/null 2>&1 && echo -n "." || echo -n "x"
}

clear_book() {
  COUNT=$(cast call "$VENUE" "orderCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
  echo -n "  cancelling live orders (of $COUNT): "
  python3 - "$VENUE" "$RPC" "$COUNT" > /tmp/live_ids.txt 2>/dev/null <<'PY'
import subprocess, sys
venue, rpc, count = sys.argv[1], sys.argv[2], int(sys.argv[3])
for i in range(count):
    out = subprocess.run(
        ["cast", "call", venue,
         "orders(uint256)(address,address,address,bool,uint256,uint256,uint256,bool)",
         str(i), "--rpc-url", rpc],
        capture_output=True, text=True).stdout.split()
    if len(out) < 8:
        continue
    size, filled, cancelled = int(out[4]), int(out[6]), out[7] == "true"
    if not cancelled and size - filled > 0:
        print(i)
PY
  while read -r ID; do
    [ -n "$ID" ] && send_q "$VENUE" "cancel(uint256)" "$ID"
  done < /tmp/live_ids.txt
  echo " done"
}

set_level() { # bid_wei ask_wei
  echo -n "  posting bid $1 ask $2: "
  send_q "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" true  2000000000000000000 "$1"
  send_q "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" false 2000000000000000000 "$2"
  echo " done"
  cast call "$VENUE" "orderCount()(uint256)" --rpc-url "$RPC" >/dev/null 2>&1 || true
}

cd "$REPO"
cargo build --release -p runtime 2>&1 | tail -1
rm -f "$STATE"

# A price path with real moves in BOTH directions, so a directional signal can be right
# some of the time and wrong some of the time. Anything else would be a rigged test.
BIDS=(1900000000000000000 2400000000000000000 1700000000000000000 2600000000000000000 2000000000000000000 2900000000000000000)
ASKS=(2100000000000000000 2600000000000000000 1900000000000000000 2800000000000000000 2200000000000000000 3100000000000000000)

{
echo "Phase 7 live learning, clean-book market simulator"
echo "Captured $(date -u '+%Y-%m-%d %H:%M:%S UTC'), chain 1952"
echo "Counterparty flow SIMULATED (chain 1952 has no other participants). Orders,"
echo "cancels and the price path are real onchain state."
echo

for i in 0 1 2 3 4 5; do
  echo "---------- level $i: bid ${BIDS[$i]} ask ${ASKS[$i]} ----------"
  clear_book
  set_level "${BIDS[$i]}" "${ASKS[$i]}"
  ASML_REPO="$REPO" ./target/release/asml learn 2 2>&1 \
    | grep -E "cycle |PARAM CHANGE|settled decision|pending"
  echo
done

echo "=================================================================="
echo "FINAL SUMMARY"
echo "=================================================================="
ASML_REPO="$REPO" ./target/release/asml learn 1 2>&1 | sed -n '/learning summary/,$p'
} 2>&1 | tee "$EVID/clean-market-run.txt"

echo
python3 -c "
import json
d = json.load(open('$STATE'))
print('params        ', json.dumps(d['params']))
print('settled       ', d['settled_count'])
print('unscored_flat ', d.get('unscored_flat'))
print('stats         ', json.dumps(d['stats']))
print('changes       ', len(d['history']))
for c in d['history']:
    print('   ', c['parameter'], c['from'], '->', c['to'], '|', c['trigger'])
" | tee "$EVID/state-after-clean.txt"
