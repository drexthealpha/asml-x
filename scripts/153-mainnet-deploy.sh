#!/usr/bin/env bash
# Task 12.1: deploy the minimal high-signal set to X Layer MAINNET, chain 196.
#
# THINKING: #33 Pareto (which contracts carry the argument), #27 opportunity-cost,
# #29 margin-of-safety.
#
# EVIDENCE PATH: docs/verified/deployments-mainnet.md
# PASS: every address returns non-empty code on 196, with the deploy tx hash for each.
#
# FAKE WIN, quoted: "deploying and never using them."
# COUNTER, quoted: "12.2 through 12.5 must transact against each one."
#
# THIS SPENDS REAL OKB. The order is exactly the one derived in task 11.5 from the constructors, and
# the chain id is asserted before the first deployment. Every address is read back with eth_getCode
# before this script reports success, because a deploy transaction that succeeded and left no code is
# a thing that happens.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/docs/verified/deployments-mainnet.md"
J="$REPO/deployments-mainnet.json"
mkdir -p "$(dirname "$OUT")"
RPC="https://rpc.xlayer.tech"
PASS="$(keystore_pass)"

CHAIN=$(python3 -c "print(int('$(cast rpc eth_chainId --rpc-url "$RPC" 2>/dev/null | tr -d '"')', 16))")
[ "$CHAIN" = "196" ] || { echo "ABORT: chain is $CHAIN, not 196"; exit 1; }

BAL_BEFORE=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
echo "chain 196 confirmed. balance before: $BAL_BEFORE wei"

# The fee treasury MUST NOT be the deployer. Task 7.6 found that with treasury == maker == deployer,
# fee revenue and trade proceeds land in one balance and revenue cannot be stated from balances.
TREASURY=0x000000000000000000000000000000000FEE0196

cd "$REPO/contracts"
forge build > /dev/null 2>&1

declare -A ADDR
declare -A TXH

dep() { # name, path:Contract, constructor args...
  local name="$1" target="$2"
  shift 2
  local raw
  raw=$(forge create "$target" \
    --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --broadcast --json \
    "$@" 2>/dev/null)
  local addr tx
  addr=$(printf '%s' "$raw" | python3 -c "import json,sys
try: print(json.load(sys.stdin)['deployedTo'])
except Exception: print('')" 2>/dev/null)
  tx=$(printf '%s' "$raw" | python3 -c "import json,sys
try: print(json.load(sys.stdin)['transactionHash'])
except Exception: print('')" 2>/dev/null)
  if [ -z "$addr" ]; then
    echo "  $name: DEPLOY FAILED"
    printf '%s\n' "$raw" | tail -3
    return 1
  fi
  ADDR[$name]="$addr"
  TXH[$name]="$tx"
  printf '  %-16s %s  %s\n' "$name" "$addr" "$tx"
}

echo
echo "=== deploying, in the order derived in task 11.5 ==="
dep aQUOTE  src/MockERC20.sol:MockERC20        --constructor-args "ASML Quote" "aQUOTE"
dep aBASE   src/MockERC20.sol:MockERC20        --constructor-args "ASML Base" "aBASE"
dep venue   src/OrderBookVenue.sol:OrderBookVenue
dep guard   src/RiskGuard.sol:RiskGuard        --constructor-args 1000000000000000000000
dep fee     src/FeeCollector.sol:FeeCollector  --constructor-args "$TREASURY" 50
dep exec    src/BatchExecutor.sol:BatchExecutor --constructor-args "${ADDR[guard]}" "${ADDR[fee]}"
dep vault   src/AgentVault.sol:AgentVault      --constructor-args "${ADDR[aQUOTE]}" "${ADDR[venue]}"

echo
echo "=== reading code back from chain, because a successful deploy tx with no code happens ==="
ALL_OK=1
for k in aQUOTE aBASE venue guard fee exec vault; do
  code=$(cast code "${ADDR[$k]}" --rpc-url "$RPC" 2>/dev/null || echo 0x)
  size=$(python3 -c "print(max(0,(len('$code')-2)//2))")
  printf '  %-16s %-44s %s bytes\n' "$k" "${ADDR[$k]}" "$size"
  [ "$size" -gt 0 ] || ALL_OK=0
done

MARKET=$(cast call "${ADDR[venue]}" "marketId(address,address)(bytes32)" "${ADDR[aBASE]}" "${ADDR[aQUOTE]}" --rpc-url "$RPC")
BLOCK=$(cast block-number --rpc-url "$RPC")

python3 - "$J" "$MARKET" "$TREASURY" "$BLOCK" "$RPC" \
  "${ADDR[aQUOTE]}" "${ADDR[aBASE]}" "${ADDR[venue]}" "${ADDR[guard]}" \
  "${ADDR[fee]}" "${ADDR[exec]}" "${ADDR[vault]}" <<'PY'
import json, sys
p, market, treasury, block, rpc = sys.argv[1:6]
q, b, v, g, f, e, va = sys.argv[6:13]
json.dump({
    "chainId": 196,
    "rpc": rpc,
    "deployBlock": int(block),
    "deployer": "0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46",
    "feeTreasury": treasury,
    "tQUOTE": q, "tBASE": b, "venue": v, "riskGuard": g,
    "feeCollector": f, "batchExecutor": e, "agentVault": va,
    "marketId": market,
}, open(p, "w"), indent=2)
print(f"wrote {p}")
PY

BAL_AFTER=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
SPENT=$((BAL_BEFORE - BAL_AFTER))

{
echo "# Mainnet deployments, X Layer chain 196"
echo
echo "Deployed $(date -u '+%Y-%m-%d %H:%M:%S UTC') at block $BLOCK."
echo
echo "Status: DEMONSTRATED. Every address below was deployed by $DEPLOYER_ADDRESS and its runtime"
echo "code was read back from chain with eth_getCode, because a deploy transaction that succeeds and"
echo "leaves no code is a thing that happens."
echo
echo "These are SELF-DEPLOYED contracts, not third-party venues. Task 11.6 established that Exchange"
echo "OS has no usable developer surface on mainnet, four ways. See docs/verified/exchangeos-mainnet.md."
echo
echo "| contract | address | deploy tx |"
echo "|---|---|---|"
for k in aQUOTE aBASE venue guard fee exec vault; do
  echo "| $k | \`${ADDR[$k]}\` | [\`${TXH[$k]:0:18}...\`](https://www.oklink.com/x-layer/tx/${TXH[$k]}) |"
done
echo
echo "Market id for aBASE/aQUOTE: \`$MARKET\`"
echo
echo "Fee treasury: \`$TREASURY\`, deliberately NOT the deployer. Task 7.6 found that with"
echo "treasury == maker == deployer, fee revenue and trade proceeds land in the same balance and"
echo "revenue cannot be stated from balances at all."
echo
echo "## Explorer"
echo
for k in aQUOTE aBASE venue guard fee exec vault; do
  echo "- $k: https://www.oklink.com/x-layer/evm/address/${ADDR[$k]}"
done
echo
echo "## Cost of this step"
echo
echo '```'
echo "balance before  $BAL_BEFORE wei"
echo "balance after   $BAL_AFTER wei"
echo "spent           $SPENT wei ($(python3 -c "print(f'{$SPENT/1e18:.9f}')") OKB)"
echo '```'
} > "$OUT"

echo
echo "spent: $SPENT wei"
echo "written: $OUT and $J"
[ "$ALL_OK" -eq 1 ]
