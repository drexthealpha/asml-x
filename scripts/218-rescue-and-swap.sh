#!/usr/bin/env bash
# Recover the WOKB stranded in the first RouterExecutor, then execute the real swap.
#
# WHY THERE IS ANYTHING TO RESCUE. The first deployment approved the router instead of the
# token-approval proxy, so its swap reverted with the WOKB already transferred in. That is exactly
# the situation `rescue()` was written for, and it is worth noting that the function was included
# because holding real value between legs makes a stuck balance a foreseeable state, not because
# this failure was anticipated.
#
# EVIDENCE PATH: evidence/phase19/first-real-swap.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.foundry/bin:$PATH"

RPC="https://rpc.xlayer.tech"
OLD_EXEC="0x02cA5dA7c7C7d9b9BbbD6C08F26f8C5281C39127"
SWAP_WOKB="${SWAP_WOKB:-0.002}"
OUT="$REPO/evidence/phase19/first-real-swap.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

PASS="$(keystore_pass)"
WOKB=$(python3 -c "import tokens;print(tokens.address('WOKB'))") || exit 1
USDT=$(python3 -c "import tokens;print(tokens.address('USDT'))") || exit 1
EXEC=$(python3 -c "import json;print(json.load(open('$REPO/deployments-mainnet.json'))['routerExecutor'])")

echo "old executor  $OLD_EXEC"
echo "new executor  $EXEC"
echo "router        $(cast call "$EXEC" 'router()(address)' --rpc-url "$RPC")"
echo "approver      $(cast call "$EXEC" 'approver()(address)' --rpc-url "$RPC")"

STRANDED=$(cast call "$WOKB" 'balanceOf(address)(uint256)' "$OLD_EXEC" --rpc-url "$RPC" | awk '{print $1}')
echo
echo "=== 1. rescue $STRANDED wei WOKB from the old executor ==="
if [ "$STRANDED" != "0" ]; then
  cast send "$OLD_EXEC" "rescue(address,address,uint256)" "$WOKB" "$EXEC" "$STRANDED" \
    --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print('  status',d['status'],'tx',d['transactionHash'])" \
    || { echo "  rescue FAILED"; exit 1; }
else
  echo "  nothing stranded"
fi
echo "  new executor WOKB $(cast call "$WOKB" 'balanceOf(address)(uint256)' "$EXEC" --rpc-url "$RPC" | awk '{print $1}')"

echo
echo "=== 2. the real swap, WOKB -> USDT across real X Layer pools ==="
USDT_BEFORE=$(cast call "$USDT" 'balanceOf(address)(uint256)' "$EXEC" --rpc-url "$RPC" | awk '{print $1}')
echo "  executor USDT before $USDT_BEFORE"

if OUTPUT=$(bash submit-swap.sh WOKB USDT "$SWAP_WOKB" 9999 2>&1); then
  echo "  $OUTPUT"
else
  echo "  SWAP FAILED:"
  echo "$OUTPUT" | sed 's/^/    /'
  exit 1
fi

USDT_AFTER=$(cast call "$USDT" 'balanceOf(address)(uint256)' "$EXEC" --rpc-url "$RPC" | awk '{print $1}')
WOKB_AFTER=$(cast call "$WOKB" 'balanceOf(address)(uint256)' "$EXEC" --rpc-url "$RPC" | awk '{print $1}')
echo "  executor USDT after  $USDT_AFTER"
echo "  executor WOKB after  $WOKB_AFTER"
echo "  USDT gained          $(python3 -c "print(($USDT_AFTER - $USDT_BEFORE)/10**6)")"
echo
echo "That gain is a balance delta read from the USDT contract, not a figure the router reported."
echo "RouterExecutor.route enforces the same measurement on chain and reverts on a shortfall."
