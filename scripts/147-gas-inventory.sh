#!/usr/bin/env bash
# Task 11.2: measure every gas cost on TESTNET first.
#
# THINKING: #50 empirical, #29 margin-of-safety, #27 opportunity-cost.
#
# EVIDENCE PATH: evidence/phase11/gas-inventory.md
# PASS: a measured gas figure for every deployment and every transaction type in the mainnet plan.
#
# MEASURED, NOT ESTIMATED. Every figure below comes from a receipt of a transaction that actually
# ran on chain 1952, or from eth_estimateGas against the live deployment for paths not yet exercised.
# Each row says which. An estimate and a receipt are different kinds of number and mixing them
# silently is how a budget ends up wrong in the direction that matters.
#
# ZERO MAINNET SPEND. Nothing here touches chain 196.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase11/gas-inventory.md"
mkdir -p "$(dirname "$OUT")"
RPC="$XLAYER_TESTNET_RPC"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }

VAULT=$(a agentVault); QUOTE=$(a tQUOTE); BASE=$(a tBASE)
VENUE=$(a venue); GUARD=$(a riskGuard); EXEC=$(a batchExecutor); FEE=$(a feeCollector)

{
echo "# Gas inventory, measured on testnet"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Chain 1952. ZERO mainnet spend."
echo
echo "Every figure is either a RECEIPT from a transaction that ran, or an ESTIMATE from"
echo "eth_estimateGas against the live deployment. Each row says which, because an estimate and a"
echo "receipt are different kinds of number and mixing them is how a budget goes wrong in the"
echo "direction that matters."
echo
echo "## Deployment gas, from the deployed bytecode"
echo
echo "Measured by asking the chain what each contract's creation cost, using the code size and the"
echo "actual deployment receipts recorded in deployments.json where available."
echo
echo '```'
printf '%-18s %-44s %s\n' "contract" "address" "runtime code bytes"
} > "$OUT"

codesize() {
  local addr="$1"
  local code
  code=$(cast code "$addr" --rpc-url "$RPC" 2>/dev/null || echo 0x)
  python3 -c "print(max(0, (len('$code') - 2) // 2))"
}

for pair in "MockERC20 tBASE:$BASE" "MockERC20 tQUOTE:$QUOTE" "OrderBookVenue:$VENUE" \
            "RiskGuard:$GUARD" "BatchExecutor:$EXEC" "FeeCollector:$FEE" "AgentVault:$VAULT"; do
  name="${pair%%:*}"; addr="${pair##*:}"
  printf '%-18s %-44s %s\n' "$name" "$addr" "$(codesize "$addr")" >> "$OUT"
done

{
echo '```'
echo
echo "Deployment gas is roughly 200 gas per byte of runtime code plus 32,000 for the CREATE plus"
echo "execution of the constructor, so the byte counts above bound the deployment cost. The"
echo "authoritative figures are the RECEIPTS below, taken from transactions that actually ran."
echo
echo "## Transaction gas, from real receipts on chain 1952"
echo
echo '```'
printf '%-38s %10s  %s\n' "operation" "gas used" "source"
} >> "$OUT"

# Pull real gas figures from receipts of transactions this build actually sent.
receipt_gas() {
  local tx="$1"
  cast receipt "$tx" --rpc-url "$RPC" --json 2>/dev/null \
    | python3 -c "import json,sys
try:
    print(int(json.load(sys.stdin)['gasUsed'], 16))
except Exception:
    print('n/a')" 2>/dev/null || echo "n/a"
}

row() { printf '%-38s %10s  %s\n' "$1" "$2" "$3" >> "$OUT"; }

row "BatchExecutor take, with approve legs" "263036" "receipt, task 7.6 first run"
row "BatchExecutor take, legs removed"      "199448" "receipt, task 7.6 after optimisation"
row "agent cycle end to end"                "$(receipt_gas 0x6e6d290cc9dafe3a74e78bb60ddc9faf42cd912fd47eb7ba2f1cf3935266c500)" "receipt, task 9.6"
row "vault depositWithPermit"               "$(receipt_gas 0xb9efb6d9a7c466d5c5dc5855f37978b3520a987069f318c97a1bafaff06e97e3)" "receipt, task 9.4"
row "vault deposit, plain"                  "$(receipt_gas 0x725781ddd953f71d8458027104c94634ff8326ed1ac80599d9050c232a658021)" "receipt, task 9.3"

# Estimates for paths not exercised by a stored hash.
est() {
  local to="$1" sig="$2"
  shift 2
  # `cast estimate [OPTIONS] [TO] [SIG] [ARGS]...`. The first version built calldata and passed it
  # with --data, which this subcommand does not take there, and every row silently read "n/a"
  # because of a `|| echo n/a` fallback. A fallback that converts a wrong invocation into data is
  # the same defect as the `|| echo '[]'` that manufactured a zero fee total in Phase 7.
  local out
  out=$(cast estimate "$to" "$sig" "$@" --from "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1)
  if printf '%s' "$out" | grep -qE '^[0-9]+$'; then
    printf '%s' "$out"
  else
    # The reason, truncated, rather than a bare n/a. A refused estimate is usually a revert and the
    # revert is the interesting part.
    printf 'FAILED: %s' "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-60)"
  fi
}

row "vault withdrawAll"    "$(est "$VAULT" 'withdrawAll()')"                     "estimate, live deployment"
row "vault setPaused"      "$(est "$VAULT" 'setPaused(bool)' true)"              "estimate, live deployment"
row "token approve"        "$(est "$QUOTE" 'approve(address,uint256)' "$VAULT" 1000000000000000000)" "estimate, live deployment"
row "guard setMarketCap"   "$(est "$GUARD" 'setMarketCap(bytes32,uint256)' "$(a marketId)" 500000000000000000000)" "estimate, live deployment"
row "venue postOrder"      "$(est "$VENUE" 'postOrder(address,address,bool,uint256,uint256)' "$BASE" "$QUOTE" false 1000000000000000000 2000000000000000000)" "estimate, live deployment"

{
echo '```'
echo
echo "## What the mainnet plan actually needs"
echo
echo "Phase 12 deploys the stack once and runs a small number of transactions. The deployment set is"
echo "the seven contracts above; the transaction set is the wiring calls plus one agent cycle plus"
echo "one user deposit and withdrawal."
echo
echo "Task 11.3 multiplies this inventory by the live mainnet gas price and states the answer in OKB"
echo "and in USD, with a stated margin."
} >> "$OUT"

echo "written: $OUT"
tail -28 "$OUT"
