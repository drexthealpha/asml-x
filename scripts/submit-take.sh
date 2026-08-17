#!/usr/bin/env bash
# Signing shim called by the Rust runtime. Takes an approved decision and submits
# it as an atomic batch through BatchExecutor.
#
# The RPC honours ASML_RPC so the same shim serves testnet and mainnet. It defaults to the testnet
# endpoint, so every existing caller is unchanged.
#
# Args: <order_id> <base_amount_wei> <quote_notional_wei> <decision_id>
# Prints: TX=<hash> on success.
#
# This exists because signing is delegated to `cast` rather than hand-rolled in
# Rust (ADR-008). The runtime decides and constructs; cast signs. Stated plainly.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

ORDER_ID="${1:?order_id required}"
BASE_AMT="${2:?base amount required}"
QUOTE_NOTIONAL="${3:?quote notional required}"
DECISION_ID="${4:?decision id required}"

J="$REPO/deployments.json"
QUOTE=$(python3 -c "import json;print(json.load(open('$J'))['tQUOTE'])")
VENUE=$(python3 -c "import json;print(json.load(open('$J'))['venue'])")
GUARD=$(python3 -c "import json;print(json.load(open('$J'))['riskGuard'])")
EXEC=$(python3 -c "import json;print(json.load(open('$J'))['batchExecutor'])")
MARKET=$(python3 -c "import json;print(json.load(open('$J'))['marketId'])")


FEE=$(python3 -c "import json;print(json.load(open('$J'))['feeCollector'])")

L1=$(cast calldata "addExposure(bytes32,uint256)" "$MARKET" "$QUOTE_NOTIONAL")
L2=$(cast calldata "take(uint256,uint256)" "$ORDER_ID" "$BASE_AMT")
# The fee leg. LAST, and enforced as last by BatchExecutor, so it is charged on a notional that has
# actually executed. The payer is the executor, which is the address that holds the quote asset.
L3=$(cast calldata "charge(address,bytes32,address,uint256)" "$EXEC" "$MARKET" "$QUOTE" "$QUOTE_NOTIONAL")

# The per-batch approve legs that used to sit here are gone. They re-set a 1e24 allowance on every
# execution, paying an SSTORE for a value that had not changed. Both allowances are granted once at
# deploy time through BatchExecutor.approveToken, which is what that function exists for.
BATCH_ID=$(printf '0x%064x' "$DECISION_ID")

OUT=$(cast send "$EXEC" "execute((address,bytes)[],bytes32)" \
  "[($GUARD,$L1),($VENUE,$L2),($FEE,$L3)]" "$BATCH_ID" \
  --rpc-url "${ASML_RPC:-$XLAYER_TESTNET_RPC}" \
  --keystore "$KEYFILE" --password "$(keystore_pass)" --json 2>&1)

STATUS=$(printf '%s' "$OUT" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('status',''))
except Exception:
    print('')" 2>/dev/null)

if [ "$STATUS" = "0x1" ]; then
  TX=$(printf '%s' "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])")
  echo "TX=$TX"
  exit 0
fi

echo "SUBMIT_FAILED status=$STATUS"
printf '%s' "$OUT" | tail -5
exit 1
