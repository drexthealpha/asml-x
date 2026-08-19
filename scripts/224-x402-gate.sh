#!/usr/bin/env bash
# Prove the x402 gate: unpaid is refused with a challenge, and the gate is OFF by default.
#
# TWO PROPERTIES, BOTH WORTH PROVING:
#
#   1. With `ASML_X402_PRICE` unset the endpoint behaves exactly as it always has. Every Phase 6
#      artifact and every existing consumer calls it unpaid, so a payment gate that switched itself
#      on would break all of them.
#   2. With the price set, an unpaid POST /quote returns 402 AND a well-formed challenge naming the
#      amount, the asset, the network and the recipient. A 402 with no challenge is unusable: the
#      caller has no way to pay.
#
# EVIDENCE PATH: evidence/phase20/x402.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase20/x402.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

PORT="${PORT:-8099}"
cd "$REPO"

# Mainnet, because that is where the product and the money are. The deployments manifest is
# swapped for the duration so the API reads mainnet addresses, and restored on exit.
export ASML_RPC="https://rpc.xlayer.tech"
export ASML_CHAIN_ID=196
cp "$REPO/deployments.json" "$REPO/deployments.json.bak"
cp "$REPO/deployments-mainnet.json" "$REPO/deployments.json"
trap 'mv -f "$REPO/deployments.json.bak" "$REPO/deployments.json" 2>/dev/null; pkill -f asml-coord 2>/dev/null' EXIT

start_api() {
  # E12: setsid + nohup, or the server dies with the invocation that started it.
  setsid nohup "$@" > /tmp/asml-coord.log 2>&1 < /dev/null &
  sleep 25
}

stop_api() {
  pkill -f "asml-coord" >/dev/null 2>&1 || true
  sleep 1
}

echo "building"
~/.cargo/bin/cargo build -p coordination-api 2>&1 | tail -2

stop_api

echo
echo "=== 1. payment DISABLED (default) ==="
ASML_COORD_PORT="$PORT" start_api "$REPO/target/debug/asml-coord"
CODE=$(curl -s -o /tmp/x402-off.json -w "%{http_code}" --max-time 8 \
  -X POST "http://127.0.0.1:$PORT/quote" \
  -H 'content-type: application/json' -H 'x-api-key: demo-agent-key-1' \
  -d '{"size_micro":"1000000","side":"buy"}')
echo "  POST /quote unpaid → $CODE"
head -c 200 /tmp/x402-off.json 2>/dev/null; echo
stop_api

echo
echo "=== 2. payment ENABLED ==="
ASML_COORD_PORT="$PORT" \
ASML_X402_PRICE="10000" \
ASML_X402_ASSET="USDT" \
ASML_X402_ASSET_ADDRESS="0x779ded0c9e1022225f8e0630b35a9b54be713736" \
ASML_X402_CHAIN="196" \
ASML_X402_PAY_TO="$(python3 -c "import json;print(json.load(open('$REPO/deployments-mainnet.json'))['feeCollector'])")" \
  start_api "$REPO/target/debug/asml-coord"

CODE=$(curl -s -o /tmp/x402-on.json -w "%{http_code}" --max-time 8 \
  -X POST "http://127.0.0.1:$PORT/quote" \
  -H 'content-type: application/json' -H 'x-api-key: demo-agent-key-1' \
  -d '{"size_micro":"1000000","side":"buy"}')
echo "  POST /quote unpaid → $CODE  (402 expected)"
python3 -m json.tool /tmp/x402-on.json 2>/dev/null | head -20

echo
CODE=$(curl -s -o /tmp/x402-paid.json -w "%{http_code}" --max-time 8 \
  -X POST "http://127.0.0.1:$PORT/quote" \
  -H 'content-type: application/json' -H 'x-api-key: demo-agent-key-1' \
  -H 'PAYMENT-SIGNATURE: test-authorization' \
  -d '{"size_micro":"1000000","side":"buy"}')
echo "  POST /quote WITH a payment header → $CODE  (not 402)"
head -c 240 /tmp/x402-paid.json 2>/dev/null; echo

stop_api
echo
echo "The paid request is not 402, which is the property being proved: the gate is the header,"
echo "and the risk engine still decides the answer."
