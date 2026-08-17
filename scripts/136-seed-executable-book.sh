#!/usr/bin/env bash
# Seed a book the agent has a REASON to trade, so the demo shows an execution and a fee event.
#
# THINKING: #60 map-territory (the agent held because holding was correct, not because it was broken),
# #22 inversion (ask what market condition makes taking the right answer), #50 empirical.
#
# THE PROBLEM. scripts/17-seed-book-and-observe.sh posts asks at 2.10 and 2.20 against bids at 1.90
# and 1.80: mid 2.00, spread 1000 bps. Crossing a 1000 bps spread costs more than the edge available,
# so the agent scores hold above every take, ten times out of ten. That is the risk engine working.
# The demo was therefore honest and incomplete: it showed thesis, refusal and a journal row, and never
# an execution or a fee event, which task 9.6 asks for.
#
# THE FIX IS NOT TO MAKE THE AGENT LESS CAUTIOUS. It is to put a trade on the book that is genuinely
# worth taking. A resting ask BELOW the best bid is a crossed book: someone is selling base for less
# than someone else will pay for it. Taking that is not a marginal call, it is the thing a market
# maker exists to do, and an agent that declined it would be broken.
#
# So the agent's judgement is untouched. What changes is the market it is judging, and the mispricing
# is real: the order is live on chain and anybody could take it.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
VENUE=$(a venue); BASE=$(a tBASE); QUOTE=$(a tQUOTE); EXEC=$(a batchExecutor)
FEE=$(a feeCollector)

send() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['status'])" 2>/dev/null || echo FAIL
}

echo "=== funding the maker and the executor ==="
echo -n "  mint tBASE to deployer:  "; send "$BASE"  "mint(address,uint256)" "$DEPLOYER_ADDRESS" 1000000000000000000000
echo -n "  mint tQUOTE to deployer: "; send "$QUOTE" "mint(address,uint256)" "$DEPLOYER_ADDRESS" 1000000000000000000000
echo -n "  mint tBASE to executor:  "; send "$BASE"  "mint(address,uint256)" "$EXEC" 500000000000000000000
echo -n "  mint tQUOTE to executor: "; send "$QUOTE" "mint(address,uint256)" "$EXEC" 500000000000000000000
echo -n "  approve venue for tBASE: "; send "$BASE"  "approve(address,uint256)" "$VENUE" 1000000000000000000000000
echo -n "  approve venue for tQUOTE:"; send "$QUOTE" "approve(address,uint256)" "$VENUE" 1000000000000000000000000

echo
echo "=== executor allowances, re-asserted ==="
echo "    A take against a resting ASK spends quote; against a resting BID it spends BASE. The"
echo "    runtime picks the side, so both must be granted. Re-asserted here because a deploy-time"
echo "    grant is setup that can be incomplete, and once was: only quote was granted, so the first"
echo "    sell reverted with LegFailed on take()."
echo -n "  exec approves venue for tQUOTE: "; send "$EXEC" "approveToken(address,address,uint256)" "$QUOTE" "$VENUE" 1000000000000000000000000
echo -n "  exec approves venue for tBASE:  "; send "$EXEC" "approveToken(address,address,uint256)" "$BASE" "$VENUE" 1000000000000000000000000
echo -n "  exec approves fee for tQUOTE:   "; send "$EXEC" "approveToken(address,address,uint256)" "$QUOTE" "$FEE" 1000000000000000000000000

echo
echo "=== the ordinary book: mid 2.00, spread 1000 bps ==="
echo -n "  ask 3 tBASE @ 2.10: "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" false 3000000000000000000 2100000000000000000
echo -n "  bid 3 tBASE @ 1.90: "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" true  3000000000000000000 1900000000000000000

echo
echo "=== the mispricing: an ask BELOW the best bid ==="
echo "    2 tBASE offered at 1.70 while a bid of 1.90 is resting. This is a crossed book: base is"
echo "    for sale at less than someone is already paying. An agent that declines this is broken."
echo -n "  ask 2 tBASE @ 1.70: "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" false 2000000000000000000 1700000000000000000
echo -n "  ask 2 tBASE @ 1.75: "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" false 2000000000000000000 1750000000000000000

echo
echo "=== book state read back from chain ==="
COUNT=$(cast call "$VENUE" "orderCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
echo "  orderCount: $COUNT"
i=$((COUNT - 4))
while [ "$i" -lt "$COUNT" ]; do
  echo "  order $i remaining: $(cast call "$VENUE" "remainingBase(uint256)(uint256)" "$i" --rpc-url "$RPC" | awk '{print $1}')"
  i=$((i + 1))
done
