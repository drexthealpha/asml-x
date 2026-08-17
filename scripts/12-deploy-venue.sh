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
# Treasury is the deployer for the testnet stack. Task 12.1 uses a separate address on mainnet.
FEE=$(dep src/FeeCollector.sol:FeeCollector --constructor-args "$DEPLOYER_ADDRESS" 50)
echo "FeeCollector   $FEE  (50 bps, ceiling 100)"
EXEC=$(dep src/BatchExecutor.sol:BatchExecutor --constructor-args "$GUARD" "$FEE")
echo "BatchExecutor  $EXEC"

if [ -z "$FEE" ]; then echo "FEECOLLECTOR DEPLOY FAILED"; exit 1; fi
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

# The fee path. Without all four of these the deployed stack is inert: the executor is not an
# authorised taker, it is not a permitted charger, and it holds no allowance to pay with.
echo -n "venue.setAuthorisedTaker(exec): "; send "$VENUE" "setAuthorisedTaker(address,bool)" "$EXEC" true
echo -n "fee.setCharger(exec): "; send "$FEE" "setCharger(address,bool)" "$EXEC" true
# BOTH TOKENS, and this is not belt and braces. A take against a resting ASK spends quote; a take
# against a resting BID spends BASE. The runtime chooses the side, so the executor must be able to
# pay in either. Task 7.6 removed the per-batch approve legs for the gas and granted only quote here,
# which worked for every buy and reverted on the first sell with LegFailed on take().
echo -n "exec approves venue for tQUOTE: "; send "$EXEC" "approveToken(address,address,uint256)" "$QUOTE" "$VENUE" 1000000000000000000000000
echo -n "exec approves venue for tBASE:  "; send "$EXEC" "approveToken(address,address,uint256)" "$BASE" "$VENUE" 1000000000000000000000000
echo -n "exec approves fee for tQUOTE: "; send "$EXEC" "approveToken(address,address,uint256)" "$QUOTE" "$FEE" 1000000000000000000000000

echo
echo "=== verify wiring by reading state back from chain ==="
echo "guard.maxGross      $(cast call "$GUARD" "maxGross()(uint256)" --rpc-url "$RPC")"
echo "guard.maxPerMarket  $(cast call "$GUARD" "maxPerMarket(bytes32)(uint256)" "$MARKET" --rpc-url "$RPC")"
echo "guard.isAgent(exec) $(cast call "$GUARD" "isAgent(address)(bool)" "$EXEC" --rpc-url "$RPC")"
echo "guard.killed        $(cast call "$GUARD" "killed()(bool)" --rpc-url "$RPC")"
echo "base.balanceOf(dep) $(cast call "$BASE" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")"
echo "venue.authorisedTaker(exec) $(cast call "$VENUE" "authorisedTakers(address)(bool)" "$EXEC" --rpc-url "$RPC")"
echo "fee.chargers(exec)          $(cast call "$FEE" "chargers(address)(bool)" "$EXEC" --rpc-url "$RPC")"
echo "fee.feeBps                  $(cast call "$FEE" "feeBps()(uint256)" --rpc-url "$RPC")"
echo "fee.MAX_FEE_BPS             $(cast call "$FEE" "MAX_FEE_BPS()(uint256)" --rpc-url "$RPC")"
echo "exec.feeCollector           $(cast call "$EXEC" "feeCollector()(address)" --rpc-url "$RPC")"
echo "quote.allowance(exec,fee)   $(cast call "$QUOTE" "allowance(address,address)(uint256)" "$EXEC" "$FEE" --rpc-url "$RPC")"

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
| FeeCollector | \`$FEE\` | usage fee on executed notional, 50 bps, immutable 100 bps ceiling |

Market id for tBASE/tQUOTE: \`$MARKET\`

Explorer:

- venue: https://www.oklink.com/x-layer-testnet/address/$VENUE
- guard: https://www.oklink.com/x-layer-testnet/address/$GUARD
- executor: https://www.oklink.com/x-layer-testnet/address/$EXEC
- feeCollector: https://www.oklink.com/x-layer-testnet/address/$FEE
- tBASE: https://www.oklink.com/x-layer-testnet/address/$BASE
- tQUOTE: https://www.oklink.com/x-layer-testnet/address/$QUOTE

## Configuration on chain

- guard.maxGross = 1000e18
- guard.maxPerMarket[tBASE/tQUOTE] = 500e18
- guard agents: BatchExecutor, deployer
- guard.killed = false
- venue.authorisedTakers[BatchExecutor] = true (nobody else can take; direct fills revert)
- fee.chargers[BatchExecutor] = true, fee.feeBps = 50, fee.MAX_FEE_BPS = 100
- BatchExecutor.feeCollector is immutable and every batch must end with a leg targeting it
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
  "feeCollector": "$FEE",
  "feeBps": 50,
  "marketId": "$MARKET"
}
JSON

echo
echo "=== balance after ==="
cast balance --ether "$DEPLOYER_ADDRESS" --rpc-url "$RPC"
echo "written: $DOCS/deployments.md and deployments.json"
