#!/usr/bin/env bash
# Compute every selector the contract-state feed needs, and read each live value off mainnet.
#
# WHY THIS EXISTS, for the fourth time. Selectors written from memory have cost this project real
# time on three separate occasions: `maxDivergenceBps`, `maxOracleAge`, `windowBufferSeconds`. A
# wrong selector does not throw. `eth_call` returns `0x`, which parses to zero, and a screen that
# should say "could not read" says "0" instead, which reads as a verified limit of nothing.
#
# So no selector goes into a feed until it appears in this file's output next to a value that came
# back from the chain.
#
# EVIDENCE PATH: evidence/phase20/contract-selectors.txt
set -uo pipefail
cd "$(dirname "$0")/../contracts"
export PATH="$HOME/.foundry/bin:$PATH"

RPC="https://rpc.xlayer.tech"
OUT="../evidence/phase20/contract-selectors.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

M="../deployments-mainnet.json"
GUARD=$(python3 -c "import json;print(json.load(open('$M'))['riskGuard'])")
VENUE=$(python3 -c "import json;print(json.load(open('$M'))['venue'])")
BATCH=$(python3 -c "import json;print(json.load(open('$M'))['batchExecutor'])")
FEE=$(python3 -c "import json;print(json.load(open('$M'))['feeCollector'])")
VAULT=$(python3 -c "import json;print(json.load(open('$M'))['agentVault'])")

probe() {
  local label="$1" addr="$2" sig="$3"
  local sel val
  sel=$(cast sig "$sig" 2>/dev/null || echo "??")
  val=$(cast call "$addr" "$sig" --rpc-url "$RPC" 2>/dev/null || echo "revert")
  printf '  %-22s %-12s %s\n' "$sig" "$sel" "${val:-0x}"
}

echo "=== RiskGuard  $GUARD"
probe guard "$GUARD" "maxGross()(uint256)"
probe guard "$GUARD" "gross()(uint256)"
probe guard "$GUARD" "killed()(bool)"
probe guard "$GUARD" "owner()(address)"
probe guard "$GUARD" "agent()(address)"

echo
echo "=== OrderBookVenue  $VENUE"
probe venue "$VENUE" "orderCount()(uint256)"
probe venue "$VENUE" "venueOwner()(address)"

echo
echo "=== BatchExecutor  $BATCH"
probe batch "$BATCH" "owner()(address)"
probe batch "$BATCH" "agent()(address)"

echo
echo "=== FeeCollector  $FEE"
probe fee "$FEE" "feeBps()(uint16)"
probe fee "$FEE" "chargeCount()(uint256)"
probe fee "$FEE" "treasury()(address)"

echo
echo "=== AgentVault  $VAULT"
probe vault "$VAULT" "totalDeposits()(uint256)"
probe vault "$VAULT" "totalCommitted()(uint256)"
probe vault "$VAULT" "isSolvent()(bool)"
probe vault "$VAULT" "paused()(bool)"
