#!/usr/bin/env bash
# Signing shim called by the Rust runtime. Takes an approved decision and submits
# it as an atomic batch through BatchExecutor.
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

BASETOK=$(python3 -c "import json;print(json.load(open('$J'))['tBASE'])")

L1=$(cast calldata "addExposure(bytes32,uint256)" "$MARKET" "$QUOTE_NOTIONAL")
APPROVE=$(cast calldata "approve(address,uint256)" "$VENUE" 1000000000000000000000000)
L4=$(cast calldata "take(uint256,uint256)" "$ORDER_ID" "$BASE_AMT")

# Approve BOTH tokens. A take against a resting bid makes us the seller, which
# moves base out of the executor, while a take against a resting ask moves quote
# out. The runtime does not tell this script which side it chose, so both
# allowances are set. Idempotent and cheap.
BATCH_ID=$(printf '0x%064x' "$DECISION_ID")

OUT=$(cast send "$EXEC" "execute((address,bytes)[],bytes32)" \
  "[($GUARD,$L1),($QUOTE,$APPROVE),($BASETOK,$APPROVE),($VENUE,$L4)]" "$BATCH_ID" \
  --rpc-url "$XLAYER_TESTNET_RPC" \
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
