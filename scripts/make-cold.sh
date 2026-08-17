#!/usr/bin/env bash
# Put the test account into a GENUINELY COLD state before measuring task 9.4.
#
# This exists because the click count is worthless measured from a warm account, and warmth is easy
# to acquire by accident. It has now happened twice: once from Phase 7's 1e24 allowance, and again
# from scripts/112c-vault-deploy.sh, which approves the vault as part of deployment. Both times the
# UI took the one-transaction path and the count looked like one click, which is true of that account
# and false of every real first visitor.
#
# Cold means:
#   allowance(user, vault) == 0     so the permit path is the one exercised
#   vault balance == 0              so this is an activation and not a top-up
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
VAULT=$(a agentVault); QUOTE=$(a tQUOTE)

send() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "?"
}

BAL=$(cast call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')
COM=$(cast call "$VAULT" "committed(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')

if [ "${COM:-0}" != "0" ]; then
  echo -n "closing an in-flight trade: "
  send "$VAULT" "closeTrade(address,uint256,uint256)" "$DEPLOYER_ADDRESS" "$COM" "$COM"
fi
if [ "${BAL:-0}" != "0" ]; then
  echo -n "withdrawing the existing balance: "
  send "$VAULT" "withdrawAll()"
fi

echo -n "clearing the allowance to zero: "
send "$QUOTE" "approve(address,uint256)" "$VAULT" 0

echo
echo "cold state, read back from chain:"
echo "  allowance(user, vault): $(cast call "$QUOTE" "allowance(address,address)(uint256)" "$DEPLOYER_ADDRESS" "$VAULT" --rpc-url "$RPC" | awk '{print $1}')"
echo "  vault.balanceOf(user):  $(cast call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')"
echo "  token.nonces(user):     $(cast call "$QUOTE" "nonces(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')"
