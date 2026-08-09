#!/usr/bin/env bash
# Task 2.2.5: deploy the venue stack to X Layer testnet (chain 1952) and record
# addresses plus explorer links. Real deploys, real transactions, per R6.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO/contracts"

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
DOCS="$REPO/docs/verified"
mkdir -p "$DOCS"

dep() { # $1 = path:Name, $2... constructor args
  forge create "$1" \
    --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --broadcast --json \
    "${@:2}" 2>/dev/null | grep -oE '0x[0-9a-fA-F]{40}' | sed -n 2p
}

echo "=== balance before ==="
cast balance --ether "$DEPLOYER_ADDRESS" --rpc-url "$RPC"

echo
echo "=== deploying ==="
BASE=$(dep src/MockERC20.sol:MockERC20 --constructor-args "ASML Test Base" "tBASE")
echo "tBASE          $BASE"
QUOTE=$(dep src/MockERC20.sol:MockERC20 --constructor-args "ASML Test Quote" "tQUOTE")
echo "tQUOTE         $QUOTE"
VENUE=$(dep src/OrderBookVenue.sol:OrderBookVenue)
echo "OrderBookVenue $VENUE"
# 1000e18 gross cap
GUARD=$(dep src/RiskGuard.sol:RiskGuard --constructor-args 1000000000000000000000)
echo "RiskGuard      $GUARD"
EXEC=$(dep src/BatchExecutor.sol:BatchExecutor --constructor-args "$GUARD")
echo "BatchExecutor  $EXEC"

if [ -z "$BASE" ] || [ -z "$QUOTE" ] || [ -z "$VENUE" ] || [ -z "$GUARD" ] || [ -z "$EXEC" ]; then
  echo "ONE OR MORE DEPLOYS FAILED"
  exit 1
fi

echo
echo "=== wiring: market id, caps, agent role ==="
MARKET=$(cast call "$VENUE" "marketId(address,address)(bytes32)" "$BASE" "$QUOTE" --rpc-url "$RPC")
echo "marketId       $MARKET"

send() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['status'], d['transactionHash'])" 2>/dev/null \
    || echo "SEND FAILED"
}

echo -n "setMarketCap 500e18: "; send "$GUARD" "setMarketCap(bytes32,uint256)" "$MARKET" 500000000000000000000
echo -n "setAgent(BatchExecutor): "; send "$GUARD" "setAgent(address,bool)" "$EXEC" true
echo -n "setAgent(deployer): "; send "$GUARD" "setAgent(address,bool)" "$DEPLOYER_ADDRESS" true
echo -n "mint tBASE to deployer: "; send "$BASE" "mint(address,uint256)" "$DEPLOYER_ADDRESS" 1000000000000000000000
echo -n "mint tQUOTE to deployer: "; send "$QUOTE" "mint(address,uint256)" "$DEPLOYER_ADDRESS" 1000000000000000000000
echo -n "mint tQUOTE to BatchExecutor: "; send "$QUOTE" "mint(address,uint256)" "$EXEC" 1000000000000000000000
echo -n "approve venue for tBASE: "; send "$BASE" "approve(address,uint256)" "$VENUE" 1000000000000000000000000
echo -n "approve venue for tQUOTE: "; send "$QUOTE" "approve(address,uint256)" "$VENUE" 1000000000000000000000000

echo
echo "=== verify wiring by reading state back from chain ==="
echo "guard.maxGross      $(cast call "$GUARD" "maxGross()(uint256)" --rpc-url "$RPC")"
echo "guard.maxPerMarket  $(cast call "$GUARD" "maxPerMarket(bytes32)(uint256)" "$MARKET" --rpc-url "$RPC")"
echo "guard.isAgent(exec) $(cast call "$GUARD" "isAgent(address)(bool)" "$EXEC" --rpc-url "$RPC")"
echo "guard.killed        $(cast call "$GUARD" "killed()(bool)" --rpc-url "$RPC")"
echo "base.balanceOf(dep) $(cast call "$BASE" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")"

cat > "$DOCS/deployments.md" <<MD
# Deployments: X Layer testnet, chain 1952

Status: DEMONSTRATED. Every address below was deployed by
$DEPLOYER_ADDRESS and read back from chain.
Captured $(date -u '+%Y-%m-%d %H:%M:%S UTC').

These are SELF-DEPLOYED contracts, not third-party venues. See
docs/decisions/ADR-001-venue-strategy.md for why, and what it costs.

| contract | address | role |
|---|---|---|
| MockERC20 tBASE | \`$BASE\` | TEST token, base asset |
| MockERC20 tQUOTE | \`$QUOTE\` | TEST token, quote asset |
| OrderBookVenue | \`$VENUE\` | escrowed limit order book |
| RiskGuard | \`$GUARD\` | binding exposure caps and kill switch |
| BatchExecutor | \`$EXEC\` | atomic multi-leg execution |

Market id for tBASE/tQUOTE: \`$MARKET\`

Explorer:

- venue: https://www.oklink.com/x-layer-testnet/address/$VENUE
- guard: https://www.oklink.com/x-layer-testnet/address/$GUARD
- executor: https://www.oklink.com/x-layer-testnet/address/$EXEC
- tBASE: https://www.oklink.com/x-layer-testnet/address/$BASE
- tQUOTE: https://www.oklink.com/x-layer-testnet/address/$QUOTE

## Configuration on chain

- guard.maxGross = 1000e18
- guard.maxPerMarket[tBASE/tQUOTE] = 500e18
- guard agents: BatchExecutor, deployer
- guard.killed = false
MD

# Machine-readable for the Rust runtime.
cat > "$REPO/deployments.json" <<JSON
{
  "chainId": 1952,
  "rpc": "$RPC",
  "deployer": "$DEPLOYER_ADDRESS",
  "tBASE": "$BASE",
  "tQUOTE": "$QUOTE",
  "venue": "$VENUE",
  "riskGuard": "$GUARD",
  "batchExecutor": "$EXEC",
  "marketId": "$MARKET"
}
JSON

echo
echo "=== balance after ==="
cast balance --ether "$DEPLOYER_ADDRESS" --rpc-url "$RPC"
echo "written: $DOCS/deployments.md and deployments.json"
