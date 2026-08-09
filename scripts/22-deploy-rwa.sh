#!/usr/bin/env bash
# Task 5.1/5.2: deploy the RWA stand-in stack to chain 1952 and record it.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO/contracts"

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"

dep() {
  forge create "$1" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" \
    --broadcast --json "${@:2}" 2>/dev/null | grep -oE '0x[0-9a-fA-F]{40}' | sed -n 2p
}
send() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo FAIL
}

echo "=== deploy RwaVault: price 1.0, window period 0 (always redeemable at start) ==="
# Period 0 keeps the window out of the way for the baseline proofs. The window
# refusal is proven later by setting a short schedule live.
VAULT=$(dep src/RwaVault.sol:RwaVault --constructor-args 1000000000000000000 0 0)
echo "RwaVault      $VAULT"

echo "=== deploy RwaRiskGuard: gross 1000e18, maxOracleAge 3600s, buffer 43200s, maxDiv 300bps ==="
RGUARD=$(dep src/RwaRiskGuard.sol:RwaRiskGuard --constructor-args \
  1000000000000000000000 "$VAULT" 3600 43200 300)
echo "RwaRiskGuard  $RGUARD"

if [ -z "$VAULT" ] || [ -z "$RGUARD" ]; then echo "DEPLOY FAILED"; exit 1; fi

RWA_MARKET=$(cast keccak "RWA/tQUOTE")
echo "rwa marketId  $RWA_MARKET"

echo
echo "=== wiring ==="
echo -n "  setMarketCap 400e18: "; send "$RGUARD" "setMarketCap(bytes32,uint256)" "$RWA_MARKET" 400000000000000000000
echo -n "  setAgent(deployer):  "; send "$RGUARD" "setAgent(address,bool)" "$DEPLOYER_ADDRESS" true

echo
echo "=== read back ==="
echo "  vault.oraclePrice   $(cast call "$VAULT" "oraclePrice()(uint256)" --rpc-url "$RPC" | awk '{print $1}')"
echo "  vault.paused        $(cast call "$VAULT" "paused()(bool)" --rpc-url "$RPC")"
echo "  vault.yieldIndex    $(cast call "$VAULT" "yieldIndex()(uint256)" --rpc-url "$RPC" | awk '{print $1}')"
echo "  guard.maxOracleAge  $(cast call "$RGUARD" "maxOracleAge()(uint256)" --rpc-url "$RPC" | awk '{print $1}')"
echo "  guard.rwaTradeable  $(cast call "$RGUARD" "rwaTradeableFlag()(bool)" --rpc-url "$RPC")"

python3 - "$VAULT" "$RGUARD" "$RWA_MARKET" <<'PY'
import json, sys, os
repo = os.environ['REPO']
p = repo + '/deployments.json'
d = json.load(open(p))
d['rwaVault'] = sys.argv[1]
d['rwaRiskGuard'] = sys.argv[2]
d['rwaMarketId'] = sys.argv[3]
json.dump(d, open(p, 'w'), indent=2)
print("deployments.json updated")
PY

cat >> "$REPO/docs/verified/deployments.md" <<MD

## RWA stand-in stack (Phase 5)

SELF-DEPLOYED STAND-IN. Not a real asset, not a third-party protocol. Deployed
because task 0.4 established no RWA-linked instrument is live on X Layer testnet.
See docs/decisions/ADR-009-rwa-standin.md.

| contract | address | role |
|---|---|---|
| RwaVault | \`$VAULT\` | oracle mark, issuer pause, redemption window, yield index |
| RwaRiskGuard | \`$RGUARD\` | RiskGuard plus four RWA-specific refusals |

RWA market id: \`$RWA_MARKET\`

- vault: https://www.oklink.com/x-layer-testnet/address/$VAULT
- rwa guard: https://www.oklink.com/x-layer-testnet/address/$RGUARD

Policy on chain: maxOracleAge 3600s, windowBuffer 43200s, maxDivergence 300 bps,
gross cap 1000e18, RWA market cap 400e18.
MD

echo "written to deployments.json and docs/verified/deployments.md"
