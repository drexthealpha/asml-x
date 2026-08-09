#!/usr/bin/env bash
# Phase 7 live proof with a MOVING market.
#
# The first live learning run produced 14 unscored samples because the venue is static:
# chain 1952 has no other participants (110 user transactions across 7 contracts in 300
# blocks, see docs/verified/chain-1952-reality.md), so nothing moves the mid.
#
# So counterparty flow is SIMULATED by this script: it posts real orders at drifting
# prices onchain, between learning cycles. Labelled plainly. The orders, the fills and
# the price path are all real onchain state; what is synthetic is the existence of a
# counterparty at all. A learning claim built on a frozen price would be meaningless,
# and pretending the flow was organic would be worse.
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

post() {
  # post <buysBase> <sizeWei> <priceWei>
  cast send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" \
    "$BASE" "$QUOTE" "$1" "$2" "$3" \
    --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo FAIL
}

cd "$REPO"
cargo build --release -p runtime 2>&1 | tail -1

echo "removing learned state for a clean cold start"
rm -f "$STATE"

# A deliberate price path with real moves in both directions, so a directional signal
# can be right sometimes and wrong sometimes. Prices in wei.
#   round : bid          ask
PATH_BIDS=(1900000000000000000 2100000000000000000 2300000000000000000 2150000000000000000 1950000000000000000 2050000000000000000 2250000000000000000)
PATH_ASKS=(2100000000000000000 2300000000000000000 2500000000000000000 2350000000000000000 2150000000000000000 2250000000000000000 2450000000000000000)

{
echo "Phase 7 live learning with a simulated moving market"
echo "Captured $(date -u '+%Y-%m-%d %H:%M:%S UTC'), chain 1952"
echo "Counterparty flow is SIMULATED by scripts/31: real onchain orders at drifting"
echo "prices, because chain 1952 has no other participants."
echo

for i in 0 1 2 3 4 5 6; do
  echo "---------- market round $i: bid ${PATH_BIDS[$i]} ask ${PATH_ASKS[$i]} ----------"
  echo -n "  post bid: "; post true  2000000000000000000 "${PATH_BIDS[$i]}"
  echo -n "  post ask: "; post false 2000000000000000000 "${PATH_ASKS[$i]}"
  echo "  running 3 learning cycles against the new price level"
  ASML_REPO="$REPO" ./target/release/asml learn 3 2>&1 | grep -E "cycle |PARAM CHANGE|settled decision"
  echo
done

echo "=================================================================="
echo "FINAL LEARNING SUMMARY"
echo "=================================================================="
ASML_REPO="$REPO" ./target/release/asml learn 1 2>&1 | sed -n '/learning summary/,$p'
} 2>&1 | tee "$EVID/moving-market-run.txt"

echo
echo "=== persisted state ==="
python3 -c "
import json
d = json.load(open('$STATE'))
print('params  ', json.dumps(d['params']))
print('settled ', d['settled_count'])
print('stats   ', json.dumps(d['stats']))
print('changes ', len(d['history']))
" | tee "$EVID/state-after-moving.txt"

echo
echo "written: $EVID/moving-market-run.txt"
