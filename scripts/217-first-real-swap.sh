#!/usr/bin/env bash
# THE FIRST REAL TRADE. OKB the deployer already holds, wrapped and swapped across real X Layer
# pools through the OKX Onchain OS router.
#
# This is the line this project has not crossed until now. Every trade before it executed against
# an order book this project deployed and seeded, which is real in the sense of being on chain and
# meaningless in the sense that we were the only participant. This one crosses PotatoSwap,
# OkieStableSwap and Uniswap V3, against liquidity nobody here provided.
#
# WHY OKB AND NOT USDT. The deployer holds OKB for gas already and holds zero USDT. Asking for USDT
# funding was an unnecessary blocker: WOKB is the deepest pair on the chain by this project's own
# measurement, and OKB wraps into it 1:1 through a payable deposit(). Verified in scripts/216.
#
# SIZE IS DELIBERATELY TINY and that costs the claim nothing. A swap of 0.002 WOKB crosses the same
# pools, pays the same fees and produces the same receipt as one of 1000. Size is a statement about
# the balance available, not about whether the trade was real.
#
# THE STEPS, each verified from chain state rather than from its own output:
#   1. wrap OKB into WOKB
#   2. move the WOKB to RouterExecutor, which is what holds tokens between legs
#   3. route a swap, with the aggregator's own minimum enforced by the contract
#
# EVIDENCE PATH: evidence/phase19/first-real-swap.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.foundry/bin:$PATH"

RPC="https://rpc.xlayer.tech"
WRAP_OKB="${WRAP_OKB:-0.003}"
SWAP_WOKB="${SWAP_WOKB:-0.002}"
OUT="$REPO/evidence/phase19/first-real-swap.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

PASS="$(keystore_pass)"
WOKB=$(python3 -c "import tokens;print(tokens.address('WOKB'))") || exit 1
USDT=$(python3 -c "import tokens;print(tokens.address('USDT'))") || exit 1
EXEC=$(python3 -c "import json;print(json.load(open('$REPO/deployments-mainnet.json'))['routerExecutor'])")
WRAP_WEI=$(python3 -c "import tokens;print(tokens.units('WOKB','$WRAP_OKB'))")

echo "executor   $EXEC"
echo "WOKB       $WOKB"
echo "USDT       $USDT"
echo "wrapping   $WRAP_OKB OKB ($WRAP_WEI wei)"

BAL=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
echo "OKB held   $(python3 -c "print(int('$BAL')/1e18)")"
if [ "$BAL" -lt "$WRAP_WEI" ]; then
  echo "ABORT: not enough OKB to wrap $WRAP_OKB and still pay gas."
  exit 1
fi

echo
echo "=== 1. wrap OKB into WOKB ==="
cast send "$WOKB" "deposit()" --value "$WRAP_WEI" \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print('  status',d['status'],'tx',d['transactionHash'])" \
  || { echo "  wrap FAILED"; exit 1; }
echo "  deployer WOKB now $(cast call "$WOKB" 'balanceOf(address)(uint256)' "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')"

echo
echo "=== 2. fund the executor ==="
cast send "$WOKB" "transfer(address,uint256)" "$EXEC" "$WRAP_WEI" \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print('  status',d['status'],'tx',d['transactionHash'])" \
  || { echo "  transfer FAILED"; exit 1; }
EXEC_BAL=$(cast call "$WOKB" 'balanceOf(address)(uint256)' "$EXEC" --rpc-url "$RPC" | awk '{print $1}')
echo "  executor WOKB now $EXEC_BAL"

echo
echo "=== 3. the real swap, WOKB -> USDT across real pools ==="
USDT_BEFORE=$(cast call "$USDT" 'balanceOf(address)(uint256)' "$EXEC" --rpc-url "$RPC" | awk '{print $1}')
echo "  executor USDT before $USDT_BEFORE"

# submit-swap.sh is the SAME shim the runtime calls. Using it here rather than a bespoke command
# means this run exercises the production path, not a parallel one that happens to work.
if OUTPUT=$(bash submit-swap.sh WOKB USDT "$SWAP_WOKB" 9999 2>&1); then
  echo "  $OUTPUT"
else
  echo "  SWAP FAILED:"
  echo "$OUTPUT" | sed 's/^/    /'
  exit 1
fi

USDT_AFTER=$(cast call "$USDT" 'balanceOf(address)(uint256)' "$EXEC" --rpc-url "$RPC" | awk '{print $1}')
echo "  executor USDT after  $USDT_AFTER"
echo "  USDT gained          $(python3 -c "print(($USDT_AFTER - $USDT_BEFORE)/10**6)")"
echo
echo "The gain above is a BALANCE DELTA read from the USDT contract, not a number the router"
echo "reported. That is the same measurement RouterExecutor.route enforces on chain."
