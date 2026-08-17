#!/usr/bin/env bash
# Stand up a local chain and a throwaway funded keystore, so the deploy, trade and settle gates run
# in CI with NO real key.
#
# THINKING: #22 inversion (what makes these gates unrunnable, and can that thing be supplied rather
# than the gates dropped), #66 failure-mode.
#
# WHY THIS EXISTS. These gates were going to be declared "local only, needs a funded key". That was
# wrong. The gates do not need THE key, they need A funded account on a chain with the right id, and
# `anvil` supplies exactly that. Skipping them would have reported green over a smaller set than a
# reader assumes, which is the failure this project spends most of its effort avoiding.
#
# WHAT IS STILL NOT SIMULATED, stated so the anvil runs are not over-read: this is a fresh chain, not
# X Layer. It has no live order flow, no other participants, and none of X Layer's OP Stack
# predeploys unless forked. What it does prove is that the deploy path, the agent loop, the risk
# gate and the settlement path work end to end against a real EVM with real transactions and real
# receipts. The mainnet claims remain what chain 196 itself records.
#
# ANVIL'S ACCOUNT 0 IS A PUBLICLY KNOWN TEST KEY. It is in anvil's own banner, in its documentation
# and in thousands of repositories. It funds nothing on any real network. Writing it here is not a
# leak, and gitleaks is configured to see it for what it is.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN_ID="${CI_CHAIN_ID:-1952}"
PORT="${CI_ANVIL_PORT:-8545}"
KEYDIR_CI="${CI_KEYDIR:-/tmp/asml-ci-keys}"
PASSWORD="ci-throwaway-not-a-secret"

# anvil's first account, deterministic and public.
ANVIL_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ANVIL_ADDR="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

mkdir -p "$KEYDIR_CI"

echo "=== starting anvil, chain id $CHAIN_ID on port $PORT ==="
# Block time 0 means instant mining, which is what makes a 100-transaction gate finish in seconds.
# --silent keeps the log readable; failures still surface through the health check below.
anvil --chain-id "$CHAIN_ID" --port "$PORT" --silent > /tmp/anvil.log 2>&1 &
ANVIL_PID=$!
echo "anvil pid $ANVIL_PID"

UP=0
for i in $(seq 1 60); do
  if cast chain-id --rpc-url "http://127.0.0.1:$PORT" > /dev/null 2>&1; then UP=$i; break; fi
  sleep 1
done
if [ "$UP" -eq 0 ]; then
  echo "anvil never answered. log:"; tail -20 /tmp/anvil.log; exit 1
fi
echo "anvil answered after ${UP}s, chain id $(cast chain-id --rpc-url "http://127.0.0.1:$PORT")"

echo
echo "=== importing anvil account 0 into a throwaway keystore ==="
# --unsafe-password because E8: cast wallet hangs waiting for a prompt otherwise under a
# non-interactive shell.
rm -f "$KEYDIR_CI/asml-deployer"
cast wallet import asml-deployer \
  --keystore-dir "$KEYDIR_CI" \
  --private-key "$ANVIL_KEY" \
  --unsafe-password "$PASSWORD" > /dev/null
printf '%s' "$PASSWORD" > "$KEYDIR_CI/keystore.pass"
echo "keystore written to $KEYDIR_CI/asml-deployer"
echo "balance: $(cast balance --ether "$ANVIL_ADDR" --rpc-url "http://127.0.0.1:$PORT") ETH"

# Emit the environment the gates need. The caller sources this, or appends it to $GITHUB_ENV.
cat > /tmp/asml-ci.env <<EOF
XLAYER_TESTNET_RPC=http://127.0.0.1:$PORT
XLAYER_TESTNET_RPC_FALLBACK=
XLAYER_TESTNET_CHAIN_ID=$CHAIN_ID
DEPLOYER_ADDRESS=$ANVIL_ADDR
KEYDIR=$KEYDIR_CI
KEYFILE=$KEYDIR_CI/asml-deployer
PASSFILE=$KEYDIR_CI/keystore.pass
ASML_RPC=http://127.0.0.1:$PORT
ASML_CHAIN_ID=$CHAIN_ID
ANVIL_PID=$ANVIL_PID
EOF

echo
echo "=== environment for the gates ==="
cat /tmp/asml-ci.env
