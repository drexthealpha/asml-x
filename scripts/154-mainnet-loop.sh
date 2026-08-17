#!/usr/bin/env bash
# Task 12.2: a complete agent loop on MAINNET. Perceive, thesis, risk gate, execute, journal.
#
# THINKING: #50 empirical, #11 systems, #60 map-territory.
#
# EVIDENCE PATH: evidence/phase12/mainnet-loop.md
# PASS: one tx hash with status 0x1 and a journal entry naming it.
#
# This wires the deployment (steps 8 to 16 of the task 11.5 plan) and then runs the real runtime
# binary against chain 196. The runtime reads deployments.json, so that file is pointed at mainnet
# for the duration and restored afterwards: the testnet deployment is still referenced by every
# Phase 7 to 10 evidence file and must not be lost.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase12/mainnet-loop.md"
mkdir -p "$(dirname "$OUT")"
RPC="https://rpc.xlayer.tech"
PASS="$(keystore_pass)"
MJ="$REPO/deployments-mainnet.json"
TJ="$REPO/deployments.json"

a() { python3 -c "import json;print(json.load(open('$MJ'))['$1'])"; }
QUOTE=$(a tQUOTE); BASE=$(a tBASE); VENUE=$(a venue); GUARD=$(a riskGuard)
FEE=$(a feeCollector); EXEC=$(a batchExecutor); VAULT=$(a agentVault); MARKET=$(a marketId)

CHAIN=$(python3 -c "print(int('$(cast rpc eth_chainId --rpc-url "$RPC" 2>/dev/null | tr -d '"')', 16))")
[ "$CHAIN" = "196" ] || { echo "ABORT: chain $CHAIN"; exit 1; }

send() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['status'])" 2>/dev/null || echo FAIL
}

echo "=== wiring, steps 8 to 15 of the deploy plan ==="
echo -n "  guard.setMarketCap:            "; send "$GUARD" "setMarketCap(bytes32,uint256)" "$MARKET" 500000000000000000000
echo -n "  guard.setAgent(exec):          "; send "$GUARD" "setAgent(address,bool)" "$EXEC" true
echo -n "  guard.setAgent(deployer):      "; send "$GUARD" "setAgent(address,bool)" "$DEPLOYER_ADDRESS" true
echo -n "  venue.setAuthorisedTaker:      "; send "$VENUE" "setAuthorisedTaker(address,bool)" "$EXEC" true
echo -n "  fee.setCharger(exec):          "; send "$FEE" "setCharger(address,bool)" "$EXEC" true
echo -n "  vault.setAgent(deployer):      "; send "$VAULT" "setAgent(address)" "$DEPLOYER_ADDRESS"

echo "=== funding, step 16 ==="
echo -n "  mint aQUOTE to deployer:       "; send "$QUOTE" "mint(address,uint256)" "$DEPLOYER_ADDRESS" 1000000000000000000000
echo -n "  mint aBASE to deployer:        "; send "$BASE"  "mint(address,uint256)" "$DEPLOYER_ADDRESS" 1000000000000000000000
echo -n "  mint aQUOTE to executor:       "; send "$QUOTE" "mint(address,uint256)" "$EXEC" 500000000000000000000
echo -n "  mint aBASE to executor:        "; send "$BASE"  "mint(address,uint256)" "$EXEC" 500000000000000000000
echo -n "  approve venue for aBASE:       "; send "$BASE"  "approve(address,uint256)" "$VENUE" 1000000000000000000000000
echo -n "  approve venue for aQUOTE:      "; send "$QUOTE" "approve(address,uint256)" "$VENUE" 1000000000000000000000000

# BOTH tokens. A take against a resting ASK spends quote; against a resting BID it spends BASE.
# Granting only quote is the Phase 7 regression that broke every sell until task 9.6 found it.
echo -n "  exec approves venue aQUOTE:    "; send "$EXEC" "approveToken(address,address,uint256)" "$QUOTE" "$VENUE" 1000000000000000000000000
echo -n "  exec approves venue aBASE:     "; send "$EXEC" "approveToken(address,address,uint256)" "$BASE"  "$VENUE" 1000000000000000000000000
echo -n "  exec approves fee aQUOTE:      "; send "$EXEC" "approveToken(address,address,uint256)" "$QUOTE" "$FEE"   1000000000000000000000000

echo "=== seeding a book worth trading ==="
echo -n "  ask 3 aBASE @ 2.10:            "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" false 3000000000000000000 2100000000000000000
echo -n "  bid 3 aBASE @ 1.90:            "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" true  3000000000000000000 1900000000000000000
echo -n "  ask 2 aBASE @ 1.70 (crossed):  "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" false 2000000000000000000 1700000000000000000
echo -n "  ask 2 aBASE @ 1.75 (crossed):  "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" false 2000000000000000000 1750000000000000000

# ---------------------------------------------------------------- run the real agent on mainnet
echo
echo "=== the agent, on chain 196 ==="
cp "$TJ" "$TJ.testnet-backup"
cp "$MJ" "$TJ"
trap 'cp "$TJ.testnet-backup" "$TJ"; rm -f "$TJ.testnet-backup"' EXIT

JBEFORE=$(grep -c . "$REPO/evidence/journal.jsonl")
cd "$REPO"
# BOTH the endpoint and the expected chain id. The first attempt set only the address book and left
# the runtime reading the testnet RPC, so orderCount() returned no bytes against a mainnet address
# and the cycle halted with RpcFailure. The chain check is what caught it, which is why it was kept
# and made configurable rather than removed.
ASML_RPC="$RPC" ASML_CHAIN_ID=196 ASML_REPO="$REPO" ./target/release/asml run 1 2>&1 | tail -14
JAFTER=$(grep -c . "$REPO/evidence/journal.jsonl")

cp "$TJ.testnet-backup" "$TJ"
rm -f "$TJ.testnet-backup"
trap - EXIT

echo
echo "journal: $JBEFORE -> $JAFTER"
echo "deployments.json restored to testnet"
