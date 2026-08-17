#!/usr/bin/env bash
# Task 7.6: emit a REAL fee event on X Layer testnet and decode it from the receipt.
#
# THINKING: #50 empirical, #60 map-territory (the chain is the territory; deployments.json is a map).
#
# EVIDENCE PATH: evidence/phase7/fee-live.txt
# PASS: a real tx hash whose receipt contains a decoded FeeCharged log with a non-zero feeAmount.
#
# The named fake win: "reading the fee from the local journal rather than from the receipt."
# COUNTER, and it is the whole design of this script: every number below is decoded from
# eth_getTransactionReceipt. Nothing is read from deployments.json except addresses, and the treasury
# balance is measured on chain before and after so the event is cross-checked against a token movement
# rather than trusted on its own. An event is a claim the contract makes about itself; a balance delta
# is what actually happened.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase7/fee-live.txt"
mkdir -p "$(dirname "$OUT")"

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"

jq_() { python3 -c "import json,sys;print(json.load(open('$J'))['$1'])"; }
VENUE=$(jq_ venue); GUARD=$(jq_ riskGuard); EXEC=$(jq_ batchExecutor)
FEE=$(jq_ feeCollector); QUOTE=$(jq_ tQUOTE); BASE=$(jq_ tBASE); MARKET=$(jq_ marketId)
TREASURY=$(cast call "$FEE" "treasury()(address)" --rpc-url "$RPC")

{
  echo "Task 7.6, live fee event on X Layer testnet (chain 1952)"
  echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  echo "chainId from chain: $(cast chain-id --rpc-url "$RPC")"
  echo "FeeCollector  $FEE"
  echo "BatchExecutor $EXEC"
  echo "treasury      $TREASURY"
  echo "feeBps        $(cast call "$FEE" "feeBps()(uint256)" --rpc-url "$RPC")"
  echo
} > "$OUT"

send() {
  cast send "$@" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>&1
}

# 1. The deployer posts a resting sell: 10e18 tBASE at 2e18 tQUOTE per 1e18 base.
echo "== posting a resting sell order ==" >> "$OUT"
POST=$(send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" \
  "$BASE" "$QUOTE" false 10000000000000000000 2000000000000000000)
POST_TX=$(printf '%s' "$POST" | python3 -c "import json,sys;print(json.load(sys.stdin)['transactionHash'])" 2>/dev/null || echo "")
ORDER_ID=$(( $(cast call "$VENUE" "orderCount()(uint256)" --rpc-url "$RPC") - 1 ))
echo "post tx:  $POST_TX" >> "$OUT"
echo "order id: $ORDER_ID" >> "$OUT"

# 2. Treasury balance BEFORE, read from chain.
BEFORE=$(cast call "$QUOTE" "balanceOf(address)(uint256)" "$TREASURY" --rpc-url "$RPC" | awk '{print $1}')
COUNT_BEFORE=$(cast call "$FEE" "chargeCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
echo "treasury tQUOTE before: $BEFORE" >> "$OUT"
echo "fee.chargeCount before: $COUNT_BEFORE" >> "$OUT"

# 3. Execute through the real signing shim the runtime uses. 10e18 base at 2e18 = 20e18 notional.
echo >> "$OUT"
echo "== executing the batch through scripts/submit-take.sh, the same shim the runtime calls ==" >> "$OUT"
SHIM=$(bash ./submit-take.sh "$ORDER_ID" 10000000000000000000 20000000000000000000 7006 2>&1)
echo "$SHIM" >> "$OUT"
TX=$(printf '%s' "$SHIM" | grep -oE 'TX=0x[0-9a-f]{64}' | cut -d= -f2)

if [ -z "$TX" ]; then
  echo "GATE: FAIL  no transaction hash returned by the shim" >> "$OUT"
  tail -30 "$OUT"; exit 1
fi

# 4. EVERYTHING BELOW IS DECODED FROM THE RECEIPT. This is the counter to the named fake win.
echo >> "$OUT"
echo "== decoding FeeCharged from eth_getTransactionReceipt ==" >> "$OUT"
# The receipt goes to a file rather than through a heredoc's stdin: a script cannot have both a
# heredoc and a here-string feeding one python invocation, and E7 says /tmp does not survive between
# wsl invocations, so it lives under $HOME for the duration of this one.
RJ="$HOME/.asml-receipt-7-6.json"
cast receipt "$TX" --rpc-url "$RPC" --json > "$RJ"
TOPIC=$(cast keccak "FeeCharged(address,bytes32,address,uint256,uint256,uint256)")
echo "event topic0: $TOPIC" >> "$OUT"

python3 - "$FEE" "$TOPIC" "$RJ" >> "$OUT" 2>&1 <<'PY'
import json, sys
fee_addr, topic = sys.argv[1].lower(), sys.argv[2].lower()
r = json.load(open(sys.argv[3]))
print("receipt status:", r["status"])
print("block:", int(r["blockNumber"], 16))
print("gas used:", int(r["gasUsed"], 16))
print("logs in receipt:", len(r["logs"]))
found = 0
for lg in r["logs"]:
    if lg["address"].lower() != fee_addr or lg["topics"][0].lower() != topic:
        continue
    found += 1
    data = lg["data"][2:]
    words = [data[i:i+64] for i in range(0, len(data), 64)]
    payer = "0x" + lg["topics"][1][-40:]
    market = lg["topics"][2]
    token = "0x" + words[0][-40:]
    notional, amount, bps = (int(w, 16) for w in words[1:4])
    print()
    print("  DECODED FeeCharged, from the receipt and nowhere else")
    print("  payer     ", payer)
    print("  market    ", market)
    print("  token     ", token)
    print("  notional  ", notional)
    print("  feeAmount ", amount)
    print("  feeBps    ", bps)
    print("  arithmetic check: notional*bps/10000 =", notional * bps // 10000,
          "==", amount, "->", notional * bps // 10000 == amount)
    print("NONZERO_FEE", amount)
print("FEE_LOGS_FOUND", found)
PY

AMOUNT=$(grep -oE '^NONZERO_FEE [0-9]+' "$OUT" | tail -1 | awk '{print $2}')
LOGS=$(grep -oE '^FEE_LOGS_FOUND [0-9]+' "$OUT" | tail -1 | awk '{print $2}')

# 5. Cross-check the event against a real token movement and the contract's own counter.
AFTER=$(cast call "$QUOTE" "balanceOf(address)(uint256)" "$TREASURY" --rpc-url "$RPC" | awk '{print $1}')
COUNT_AFTER=$(cast call "$FEE" "chargeCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
DELTA=$(python3 -c "print($AFTER - $BEFORE)")

{
  echo
  echo "== cross-check: the event against what actually moved =="
  echo "treasury tQUOTE after:  $AFTER"
  echo "treasury delta:         $DELTA"
  echo "event feeAmount:        ${AMOUNT:-none}"
  echo "fee.chargeCount after:  $COUNT_AFTER (was $COUNT_BEFORE)"
  echo
  echo "explorer:"
  echo "  https://www.oklink.com/x-layer-testnet/tx/$TX"
  echo "  https://www.oklink.com/x-layer-testnet/address/$FEE"
  echo
} >> "$OUT"

if [ "${LOGS:-0}" -ge 1 ] && [ "${AMOUNT:-0}" -gt 0 ] && [ "$DELTA" = "${AMOUNT:-x}" ] \
   && [ "$COUNT_AFTER" -eq $((COUNT_BEFORE + 1)) ]; then
  echo "GATE: PASS  tx $TX carries a decoded FeeCharged with feeAmount $AMOUNT," >> "$OUT"
  echo "            matched by a treasury balance delta of $DELTA and chargeCount $COUNT_BEFORE -> $COUNT_AFTER" >> "$OUT"
else
  echo "GATE: FAIL  logs=$LOGS amount=${AMOUNT:-none} delta=$DELTA count=$COUNT_BEFORE->$COUNT_AFTER" >> "$OUT"
fi

tail -40 "$OUT"
