#!/usr/bin/env bash
# Does withdraw(huge) from a ZERO-BALANCE address surface InsufficientBalance?
#
# If it does, the failure-path audit can run in CI with a throwaway key and no funds: the revert
# happens at estimation, so nothing is spent and no real key is needed. If it does not, the audit
# needs a funded depositor and that has to be said rather than worked around.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CAST="$HOME/.foundry/bin/cast"
RPC="$XLAYER_TESTNET_RPC"
VAULT=$(python3 -c "import json;print(json.load(open('$REPO/deployments.json'))['agentVault'])")
# An address with no deposit and no gas.
NOBODY=0x000000000000000000000000000000000000dEaD

echo "vault  $VAULT"
echo "caller $NOBODY (no deposit, no gas)"
echo
echo "=== withdrawable(NOBODY) ==="
"$CAST" call "$VAULT" "withdrawable(address)(uint256)" "$NOBODY" --rpc-url "$RPC"

echo
echo "=== eth_call withdraw(1e24) as NOBODY ==="
"$CAST" call "$VAULT" "withdraw(uint256)" 1000000000000000000000000 --from "$NOBODY" --rpc-url "$RPC" 2>&1 | head -3

echo
echo "=== selector for InsufficientBalance(uint256,uint256) ==="
"$CAST" sig "InsufficientBalance(uint256,uint256)"
