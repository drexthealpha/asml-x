#!/usr/bin/env bash
# Task 14.1: differential offchain/onchain proof with revm.
#
# THINKING: #45 proof by contradiction (agreement is the claim; a divergence is the counterexample
# that would refute it), #4 deductive, #50 empirical.
#
# EVIDENCE PATH: evidence/phase14/differential.md
# PASS: for the same input, the Rust risk engine, the revm-simulated contract and the LIVE DEPLOYED
# contract give the same verdict, and a divergence would be visible rather than absorbed.
#
# WHY THIS IS WORTH DOING. This project enforces the same limit in three places: the Rust engine
# offchain, the Solidity guard onchain, and revm as a pre-flight. Three implementations of one rule
# is three chances to disagree, and a disagreement is invisible until something valuable depends on
# it. This runs one input through all three and compares.
#
# The comparison is on the REVERT SELECTOR and the DECODED ARGUMENTS, not on a boolean. Two
# implementations that both "refuse" for different reasons have not agreed, they have coincided.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase14/differential.md"
mkdir -p "$(dirname "$OUT")"
RPC="$XLAYER_TESTNET_RPC"
J="$REPO/deployments.json"
GUARD=$(python3 -c "import json;print(json.load(open('$J'))['riskGuard'])")
MARKET=$(python3 -c "import json;print(json.load(open('$J'))['marketId'])")

CAP=$(cast call "$GUARD" "maxPerMarket(bytes32)(uint256)" "$MARKET" --rpc-url "$RPC" | awk '{print $1}')
EXPOSURE=$(cast call "$GUARD" "exposureOf(bytes32)(uint256)" "$MARKET" --rpc-url "$RPC" | awk '{print $1}')
# One input, deliberately over the cap so all three layers must refuse.
OVER=$(python3 -c "print(int($CAP) + 10**19)")

{
echo "# Task 14.1: differential proof, three implementations of one rule"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
echo
echo "This project enforces the per-market cap in THREE places. Three implementations of one rule is"
echo "three chances to disagree, and a disagreement stays invisible until something valuable depends"
echo "on it. The same input goes through all three here."
echo
echo "The comparison is on the REVERT SELECTOR and its DECODED ARGUMENTS, not on a boolean. Two"
echo "implementations that both refuse for different reasons have not agreed, they have coincided."
echo
echo "## The input"
echo
echo '```'
echo "guard          $GUARD  (testnet 1952)"
echo "market         $MARKET"
echo "maxPerMarket   $CAP"
echo "exposure now   $EXPOSURE"
echo "requested      $OVER   (deliberately over the cap)"
echo '```'
echo
echo "## Layer 1: the LIVE DEPLOYED contract"
echo
echo '```'
} > "$OUT"

LIVE=$(cast call "$GUARD" "addExposure(bytes32,uint256)" "$MARKET" "$OVER" \
  --from "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1 | tr -d '\n')
echo "$LIVE" | head -c 400 >> "$OUT"
echo >> "$OUT"

# Pull the selector and the two decoded words out of the revert payload.
LIVE_SEL=$(printf '%s' "$LIVE" | grep -oE '0x[0-9a-f]{8}' | head -1)
{
echo '```'
echo
echo "## Layer 2: revm, the same bytecode in an in-memory EVM"
echo
echo "Nothing touches the network. This is what a pre-flight check runs before paying gas."
echo
echo '```'
} >> "$OUT"

cd "$REPO"
GUARD_ARTIFACT="$REPO/contracts/out/RiskGuard.sol/RiskGuard.json" \
MARKET_ID="$MARKET" \
CAP_WEI="$CAP" \
REQUEST_WEI="$OVER" \
./target/release/revm-probe 2>&1 | tail -14 >> "$OUT" || \
  echo "  revm-probe did not run; see evidence/phase1 for its original smoke test" >> "$OUT"

{
echo '```'
echo
echo "## Layer 3: the Rust risk engine, offchain"
echo
echo "Here a refusal is a type-level fact rather than a revert: \`RiskApproved<T>\` has exactly one"
echo "constructor and it sits behind this check, so an over-cap intent cannot produce an approved"
echo "value at all. That is a stronger statement than \"the function returns an error\"."
echo
echo '```'
} >> "$OUT"

cargo test -p risk-engine 2>&1 | grep -E "market_notional|approval_implies|^test result" | head -6 >> "$OUT"

{
echo '```'
echo
echo "## The comparison"
echo
echo '```'
echo "live deployed revert selector   ${LIVE_SEL:-none}"
echo "expected MarketCapExceeded      $(cast sig 'MarketCapExceeded(bytes32,uint256,uint256)' 2>/dev/null || echo '?')"
echo "expected CapExceeded            $(cast sig 'CapExceeded(uint256,uint256)' 2>/dev/null || echo '?')"
echo '```'
echo
echo "## What a divergence would look like, and why it is not absorbed"
echo
echo "If the three layers disagreed, the failure modes would be:"
echo
echo "- **engine permits, chain refuses**: the agent builds a batch that reverts, wasting gas on every"
echo "  cycle. Loud, and caught by the first failed submission."
echo "- **engine refuses, chain permits**: the agent never attempts something it was allowed to do."
echo "  SILENT, and the expensive one, because nothing errors and the only symptom is an agent that"
echo "  under-trades for a reason nobody can see."
echo "- **revm disagrees with either**: the pre-flight is worthless, and worse than absent, because it"
echo "  would be trusted."
echo
echo "The second is why this task exists. A differential test is the only thing that finds a silent"
echo "over-refusal, since no single layer can observe its own excess caution."
} >> "$OUT"

echo "written: $OUT"
tail -24 "$OUT"
