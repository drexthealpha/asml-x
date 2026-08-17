#!/usr/bin/env bash
# Stand up the FULL local environment the browser gates need, then run them.
#
# One consistent chain for everything. The three failures this fixes all came from the pieces
# disagreeing about which chain they were on:
#
#   - the UI manifest named testnet contracts while the provider talked to a local chain, so reads
#     failed and an induced "insufficient balance" surfaced as "Failed to fetch";
#   - with everything on testnet, the signer's throwaway key had no gas, so `cast send` failed
#     estimation with "gas required exceeds allowance (0)" before the vault could revert;
#   - the coordination API read the real testnet for a venue that existed only locally, and returned
#     503 on /thesis for 450 seconds, which looked exactly like a slow warm-up.
#
# EVIDENCE PATH: evidence/phase18/browser-gates.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase18/browser-gates.txt"
mkdir -p "$(dirname "$OUT")"

echo "=== 1. local chain ==="
bash 196-ci-anvil-up.sh > /tmp/env-anvil.log 2>&1 || { tail -20 /tmp/env-anvil.log; exit 1; }
set -a; . /tmp/asml-ci.env; set +a
. ./lib.sh
echo "  chain $(cast chain-id --rpc-url "$XLAYER_TESTNET_RPC") at $XLAYER_TESTNET_RPC"

echo
echo "=== 2. deploy and seed onto it ==="
bash 197-ci-onchain-gates.sh > /tmp/env-deploy.log 2>&1 || { tail -25 /tmp/env-deploy.log; exit 1; }
grep -E "PASS|FAIL" /tmp/env-deploy.log | sed 's/^/  /'

echo
echo "=== 3. point the built UI at the local deployment ==="
python3 201-ci-ui-manifest-local.py | sed 's/^/  /'

echo
echo "=== 4. fund the signer key on the local chain, then start it ==="
# The signer's key needs gas here, which is the whole reason a local chain is used: on testnet an
# unfunded key fails estimation before the contract can revert, and funding it would need real value.
SIGNER_RPC="$XLAYER_TESTNET_RPC" bash 200-ci-signer-up.sh > /tmp/env-signer.log 2>&1 || {
  tail -20 /tmp/env-signer.log; exit 1; }
SIGNER_ADDR=$(cast wallet address --keystore "${CI_KEYDIR:-/tmp/asml-ci-keys}/ci-signer" \
  --password "ci-throwaway-not-a-secret" 2>/dev/null)
echo "  signer $SIGNER_ADDR"
cast send "$SIGNER_ADDR" --value 10ether \
  --rpc-url "$XLAYER_TESTNET_RPC" \
  --keystore "$KEYFILE" --password "$(cat "$PASSFILE")" \
  --json > /dev/null 2>&1 && echo "  funded with 10 ETH" || echo "  FUNDING FAILED"
echo "  balance: $(cast balance --ether "$SIGNER_ADDR" --rpc-url "$XLAYER_TESTNET_RPC")"

echo
echo "=== 5. coordination API on the same chain ==="
pkill -x asml-coord 2>/dev/null || true
sleep 1
ASML_REPO="$REPO" ASML_COORD_PORT=8737 ASML_RPC="$XLAYER_TESTNET_RPC" \
  setsid nohup "$REPO/target/release/asml-coord" > /tmp/env-coord.log 2>&1 < /dev/null &
for i in $(seq 1 60); do
  C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H 'x-api-key: demo-agent-key-1' \
      http://127.0.0.1:8737/thesis || echo 000)
  [ "$C" = "200" ] && break
  sleep 5
done
echo "  thesis: $C"

echo
echo "=== 6. serve the built UI ==="
pkill -f "http.server 4173" 2>/dev/null || true
sleep 1
( cd "$REPO/ui-v2/dist" && setsid nohup python3 -m http.server 4173 --bind 0.0.0.0 > /tmp/env-ui.log 2>&1 < /dev/null & )
for i in $(seq 1 30); do curl -sf -o /dev/null http://127.0.0.1:4173/ && break; sleep 1; done
echo "  ui: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4173/)"

echo
echo "=== 7. browser gates ==="
cd "$REPO/ci/browser"
ASML_PROVIDER_RPC="$XLAYER_TESTNET_RPC" \
ASML_ADDRESS="$DEPLOYER_ADDRESS" \
  node run-gates.mjs 2>&1 | tee "$OUT"
RC=${PIPESTATUS[0]}

echo
echo "written: $OUT"
exit "$RC"
