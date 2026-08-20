#!/usr/bin/env bash
# Tasks 3 and 5: what a USER can actually call on RiskGuard and FeeCollector, and the selectors.
#
# THE QUESTION THAT MATTERS. Most writes on these two contracts are `onlyOwner`, so putting them in
# a user-facing UI would be building a button that always reverts. `kill(string)` is NOT owner-
# gated in the source, which makes it the one emergency control a user might legitimately reach,
# so its actual access rule is read here rather than assumed from its name.
#
# `quoteFee(uint256)` is a view that returns the fee for a given notional. That is exactly what
# task 5.6 needs: the cost shown BEFORE signing, computed by the contract that will charge it,
# rather than by multiplying in the UI and hoping the two agree.
#
# EVIDENCE PATH: evidence/phase21/guard-fee-surface.txt
set -uo pipefail
cd "$(dirname "$0")/../contracts"
export PATH="$HOME/.foundry/bin:$PATH"

OUT="../evidence/phase21/guard-fee-surface.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

RPC="https://rpc.xlayer.tech"
GUARD=$(python3 -c "import json;print(json.load(open('../deployments-mainnet.json'))['riskGuard'])")
FEE=$(python3 -c "import json;print(json.load(open('../deployments-mainnet.json'))['feeCollector'])")

echo "=== who can call kill() ==="
sed -n '118,140p' src/RiskGuard.sol

echo
echo "=== selectors ==="
for s in "kill(string)" "killed()" "maxGross()" "gross()" "marketCap(bytes32)" "quoteFee(uint256)" "feeBps()" "treasury()" "chargeCount()"; do
  printf '  %-26s %s\n' "$s" "$(cast sig "$s")"
done

echo
echo "=== quoteFee, live, for real amounts ==="
for n in 1000000000000000000 5000000000000000000 100000000000000000000; do
  V=$(cast call "$FEE" "quoteFee(uint256)(uint256)" "$n" --rpc-url "$RPC" 2>/dev/null || echo revert)
  printf '  notional %-24s fee %s\n' "$n" "$V"
done

echo
echo "=== guard state ==="
for s in "maxGross()(uint256)" "gross()(uint256)" "killed()(bool)"; do
  printf '  %-22s %s\n' "$s" "$(cast call "$GUARD" "$s" --rpc-url "$RPC" 2>/dev/null || echo revert)"
done
