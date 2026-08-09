#!/usr/bin/env bash
# Tasks 0.2.7 and 0.2.8: deploy a trivial contract and land one real
# state-changing transaction on X Layer testnet (chain 1952).
# Produces the R6 evidence for the entire project.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

EVID="$REPO/evidence"
mkdir -p "$EVID"
cd "$REPO/contracts"

echo "=== build ==="
forge build 2>&1 | tail -5 || exit 1

echo
echo "=== deploy Ping to chain 1952 ==="
forge create src/Ping.sol:Ping \
  --rpc-url "$XLAYER_TESTNET_RPC" \
  --keystore "$KEYFILE" \
  --password "$(keystore_pass)" \
  --broadcast \
  --json > /tmp/ping-deploy.json 2>/tmp/ping-deploy.err

if [ ! -s /tmp/ping-deploy.json ]; then
  echo "DEPLOY FAILED, stderr:"
  tail -20 /tmp/ping-deploy.err
  exit 1
fi

cat /tmp/ping-deploy.json
ADDR=$(grep -oE '0x[0-9a-fA-F]{40}' /tmp/ping-deploy.json | sed -n 2p)
DEPLOY_TX=$(grep -oE '0x[0-9a-fA-F]{64}' /tmp/ping-deploy.json | head -1)

echo
echo "deployed_to: $ADDR"
echo "deploy_tx:   $DEPLOY_TX"

echo
echo "=== send one state-changing tx: ping() ==="
cast send "$ADDR" "ping()" \
  --rpc-url "$XLAYER_TESTNET_RPC" \
  --keystore "$KEYFILE" \
  --password "$(keystore_pass)" \
  --json > /tmp/ping-call.json 2>/tmp/ping-call.err

if [ ! -s /tmp/ping-call.json ]; then
  echo "PING CALL FAILED, stderr:"
  tail -20 /tmp/ping-call.err
  exit 1
fi

PING_TX=$(python3 -c "import json;print(json.load(open('/tmp/ping-call.json'))['transactionHash'])")
STATUS=$(python3 -c "import json;print(json.load(open('/tmp/ping-call.json'))['status'])")
GASUSED=$(python3 -c "import json;print(json.load(open('/tmp/ping-call.json'))['gasUsed'])")

echo "ping_tx:  $PING_TX"
echo "status:   $STATUS"
echo "gas_used: $GASUSED ($(cast to-dec "$GASUSED" 2>/dev/null))"

echo
echo "=== read state back from chain (prove it changed) ==="
COUNT=$(cast call "$ADDR" "count()(uint256)" --rpc-url "$XLAYER_TESTNET_RPC")
echo "count_onchain: $COUNT"

echo
echo "=== write evidence ==="
{
  echo "# Evidence: first real transaction on X Layer testnet"
  echo
  echo "Status: DEMONSTRATED"
  echo "Captured: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  echo "| field | value |"
  echo "|---|---|"
  echo "| chain id | 1952 (X Layer testnet, verified live) |"
  echo "| rpc | $XLAYER_TESTNET_RPC |"
  echo "| deployer | $DEPLOYER_ADDRESS |"
  echo "| contract | Ping |"
  echo "| address | $ADDR |"
  echo "| deploy tx | $DEPLOY_TX |"
  echo "| ping tx | $PING_TX |"
  echo "| ping status | $STATUS (0x1 = success) |"
  echo "| gas used | $(cast to-dec "$GASUSED" 2>/dev/null) |"
  echo "| count read back from chain | $COUNT |"
  echo
  echo "Explorer links (public, no auth):"
  echo
  echo "- contract: https://www.oklink.com/x-layer-testnet/address/$ADDR"
  echo "- deploy tx: https://www.oklink.com/x-layer-testnet/tx/$DEPLOY_TX"
  echo "- ping tx: https://www.oklink.com/x-layer-testnet/tx/$PING_TX"
  echo
  echo "Ping is not part of the product. It exists solely to prove, per standing"
  echo "rule R6, that this project can deploy and transact against the real chain"
  echo "rather than a local fork. Superseded by the Phase 2 risk guard contract."
} > "$EVID/first-tx.md"

echo "written: $EVID/first-tx.md"
