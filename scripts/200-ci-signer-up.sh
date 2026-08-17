#!/usr/bin/env bash
# Start the test signer with a THROWAWAY key, so the failure-path audit can send a real transaction
# in CI without any funded key.
#
# WHY THE AUDIT NEEDS THIS. Case 4 induces an insufficient balance by calling `withdraw(1e24)`
# through the provider with `eth_sendTransaction`. The provider does not sign; it posts to this
# endpoint, which shells out to `cast send`. With no signer running the page gets "Failed to fetch",
# the app correctly reports a network problem, and the audit correctly refuses it. That looked like
# an app defect and was a missing service.
#
# WHY A THROWAWAY KEY IS ENOUGH, measured rather than assumed. scripts/probe-insufficient-revert.sh
# calls `withdraw(1e24)` from 0x…dEaD, an address with no deposit and no gas, and the vault reverts
# with 0xcf479181 = InsufficientBalance(1e24, 0). The revert happens during estimation, so nothing is
# spent and no balance is required. The audit gets the same revert a funded depositor would get for
# asking for more than they hold, which is the case under test.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

KEYDIR_CI="${CI_KEYDIR:-/tmp/asml-ci-keys}"
PASSWORD="ci-throwaway-not-a-secret"
PORT="${SIGNER_PORT:-4177}"
mkdir -p "$KEYDIR_CI"

# A key generated fresh for this run. It holds nothing anywhere, and unlike anvil's account 0 it is
# not a well-known address, so nothing can be confused for a funded account.
if [ ! -f "$KEYDIR_CI/ci-signer" ]; then
  cast wallet import ci-signer \
    --keystore-dir "$KEYDIR_CI" \
    --private-key "$(cast wallet new --json | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["private_key"])')" \
    --unsafe-password "$PASSWORD" > /dev/null
fi
printf '%s' "$PASSWORD" > "$KEYDIR_CI/signer.pass"

pkill -f test_signer.py 2>/dev/null || true
sleep 1

# THE SIGNER'S ALLOWLIST READS $REPO/deployments.json, and that file is restored to the real testnet
# record by scripts/197. Pointed at the repo it therefore refuses the LOCAL vault with "destination
# is not a deployed contract in deployments.json", which the failure-path audit then reports as an
# app failure. Given a directory holding the local-chain deployment instead, the allowlist permits
# exactly the contracts that exist on the chain the signer is talking to, which is what the control
# is for.
SIGNER_REPO="$REPO"
if [ -f /tmp/asml-ci-deployments.json ]; then
  SIGNER_REPO=/tmp/asml-signer-repo
  mkdir -p "$SIGNER_REPO"
  cp /tmp/asml-ci-deployments.json "$SIGNER_REPO/deployments.json"
  echo "allowlist sourced from the local-chain deployment"
fi

REPO="$SIGNER_REPO" \
RPC="${SIGNER_RPC:-$XLAYER_TESTNET_RPC}" \
KEYFILE="$KEYDIR_CI/ci-signer" \
KEYPASS="$PASSWORD" \
SIGNER_PORT="$PORT" \
setsid nohup python3 "$REPO/scripts/test_signer.py" > /tmp/signer.log 2>&1 < /dev/null &

for i in $(seq 1 30); do
  if curl -sf -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/" 2>/dev/null; then break; fi
  # The endpoint may only answer POST; a refused connection is what we are waiting out.
  if curl -s -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/" 2>/dev/null; then break; fi
  sleep 1
done

if curl -s -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/"; then
  echo "signer answering on $PORT"
else
  echo "signer did not come up"
  tail -20 /tmp/signer.log
  exit 1
fi
