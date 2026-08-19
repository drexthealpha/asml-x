#!/usr/bin/env bash
# Deploy RouterExecutor to X Layer MAINNET, pinned to the live OKX Onchain OS router.
#
# This is the contract that lets the agent trade REAL tokens across REAL pools. Everything up to
# now priced real markets and then executed on an order book this project deployed.
#
# THE ROUTER ADDRESS IS NOT TYPED HERE. It is read from a live `swap` quote, because the router is
# OKX's contract and its address is a fact about the chain rather than something this repo may
# assert. A hardcoded router in a contract that forwards opaque calldata is precisely the mistake
# worth avoiding.
#
# SAFETY BEFORE SPEND, in order:
#   - chain must be 196
#   - the router address must come back from a live quote and be a CONTRACT (non-empty code)
#   - the deployer must hold gas
#   - the full test suite, including the mutation proof, must be green
#
# EVIDENCE PATH: evidence/phase19/router-executor-deploy.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

export PATH="$HOME/.foundry/bin:$PATH"
RPC="https://rpc.xlayer.tech"
OUT="$REPO/evidence/phase19/router-executor-deploy.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

echo "=== preconditions ==="
CHAIN=$(python3 -c "print(int('$(cast rpc eth_chainId --rpc-url "$RPC" | tr -d '\"')', 16))")
echo "chain                $CHAIN"
[ "$CHAIN" = "196" ] || { echo "ABORT: not chain 196"; exit 1; }

ROUTER=$(python3 router_addr.py) || { echo "ABORT: could not read the router from a live quote"; exit 1; }
APPROVER=$(python3 approver_addr.py) || { echo "ABORT: could not read the token-approval proxy"; exit 1; }
echo "approver, from API  $APPROVER"
echo "router, from quote   $ROUTER"

CODE=$(cast code "$ROUTER" --rpc-url "$RPC" 2>/dev/null | head -c 12)
[ -n "$CODE" ] && [ "$CODE" != "0x" ] || { echo "ABORT: the router address holds no code"; exit 1; }
echo "router has code      yes"

BAL=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
echo "deployer             $DEPLOYER_ADDRESS"
echo "gas, OKB             $(python3 -c "print(int('$BAL')/1e18)")"
[ "$BAL" -gt 500000000000000 ] || { echo "ABORT: under 0.0005 OKB, too thin to finish a deploy"; exit 1; }

echo
echo "=== tests must be green before anything is spent ==="
cd "$REPO/contracts"
forge test --match-contract RouterExecutorTest 2>&1 | tail -3
forge test --match-contract RouterExecutorTest >/dev/null 2>&1 || { echo "ABORT: tests are red"; exit 1; }

echo
echo "=== deploy ==="
PASS="$(keystore_pass)"
RESULT=$(forge create src/RouterExecutor.sol:RouterExecutor \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" \
  --broadcast --constructor-args "$ROUTER" "$APPROVER" 2>&1)
echo "$RESULT" | tail -6

ADDR=$(echo "$RESULT" | grep -oE "Deployed to: 0x[a-fA-F0-9]{40}" | awk '{print $3}')
TX=$(echo "$RESULT" | grep -oE "Transaction hash: 0x[a-fA-F0-9]{64}" | awk '{print $3}')
[ -n "$ADDR" ] || { echo "ABORT: no address in the deploy output"; exit 1; }

echo
echo "=== verify from chain, not from the deploy output ==="
echo "address              $ADDR"
echo "tx                   $TX"
echo "explorer             https://www.oklink.com/x-layer/evm/address/$ADDR"
echo "router,   read back  $(cast call "$ADDR" "router()(address)" --rpc-url "$RPC")"
echo "approver, read back  $(cast call "$ADDR" "approver()(address)" --rpc-url "$RPC")"
echo "owner,  read back    $(cast call "$ADDR" "owner()(address)" --rpc-url "$RPC")"

echo
echo "=== authorise the agent ==="
cast send "$ADDR" "setAgent(address)" "$DEPLOYER_ADDRESS" \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
  | python3 -c "import json,sys;print('  setAgent status', json.load(sys.stdin)['status'])" 2>/dev/null \
  || echo "  setAgent FAILED"
echo "agent,  read back    $(cast call "$ADDR" "agent()(address)" --rpc-url "$RPC")"

python3 - "$ADDR" "$ROUTER" <<'PY'
import json, os, sys
repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in dir() else os.getcwd()
repo = os.path.abspath(os.path.join(os.path.dirname(sys.argv[0]) or ".", ".."))
p = os.path.join(repo, "deployments-mainnet.json")
d = json.load(open(p, encoding="utf-8"))
d["routerExecutor"] = sys.argv[1]
d["okxRouter"] = sys.argv[2]
json.dump(d, open(p, "w", encoding="utf-8", newline="\n"), indent=2)
print(f"recorded routerExecutor and okxRouter in {p}")
PY
