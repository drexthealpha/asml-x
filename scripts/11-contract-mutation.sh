#!/usr/bin/env bash
# Task 2.2.4: mutation gate for the contracts. Same method as the Rust gate.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO/contracts"

G="src/RiskGuard.sol"
V="src/OrderBookVenue.sol"
GBAK="$HOME/.asml-mut-riskguard.sol"
VBAK="$HOME/.asml-mut-venue.sol"
OUT="$REPO/evidence/mutation-contracts.md"
cp "$G" "$GBAK"; cp "$V" "$VBAK"
restore() { cp "$GBAK" "$G"; cp "$VBAK" "$V"; }
trap restore EXIT

quiet() { forge test >/dev/null 2>&1; }

{
  echo "# Mutation gate: contracts"
  echo
  echo "Task 2.2.4, standing rule R7. Captured $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
  echo
  echo "| # | mutation | result |"
  echo "|---|---|---|"
} > "$OUT"

echo "=== baseline ==="
if quiet; then echo "baseline GREEN"; else echo "BASELINE RED, abort"; forge test 2>&1 | tail -20; exit 1; fi

N=0; PASS=0; FAIL=0
mut() { # label, file, sed, sentinel
  N=$((N+1)); restore
  sed -i "$3" "$2"
  if ! grep -qF "$4" "$2"; then
    echo "  [$1] sed did not apply"
    printf '| %s | %s | sed did not apply |\n' "$N" "$1" >> "$OUT"; FAIL=$((FAIL+1)); restore; return
  fi
  if quiet; then
    echo "  [$1] STAYED GREEN  <-- gap"
    printf '| %s | %s | **STAYED GREEN, TEST GAP** |\n' "$N" "$1" >> "$OUT"; FAIL=$((FAIL+1))
  else
    echo "  [$1] RED (good)"
    printf '| %s | %s | RED, test holds |\n' "$N" "$1" >> "$OUT"; PASS=$((PASS+1))
  fi
  restore
}

echo
echo "=== mutations: RiskGuard ==="
mut "market cap check removed" "$G" \
  's|if (nextMarket > cap) revert MarketCapExceeded(market, nextMarket, cap);||' \
  'uint256 nextGross = gross + amount;'
mut "market cap: > to >=" "$G" \
  's|if (nextMarket > cap) revert|if (nextMarket >= cap) revert|' \
  'nextMarket >= cap'
mut "gross cap check removed" "$G" \
  's|if (nextGross > maxGross) revert GrossCapExceeded(nextGross, maxGross);||' \
  'exposureOf[market] = nextMarket;'
mut "notKilled removed from addExposure" "$G" \
  's|external onlyAgent notKilled|external onlyAgent|' \
  'uint256 amount) external onlyAgent {'
mut "revive becomes agent-callable" "$G" \
  's|function revive() external onlyOwner|function revive() external|' \
  'function revive() external {'
mut "setMarketCap loses onlyOwner" "$G" \
  's|function setMarketCap(bytes32 market, uint256 cap) external onlyOwner|function setMarketCap(bytes32 market, uint256 cap) external|' \
  'uint256 cap) external {'
mut "unconfigured market no longer fails closed" "$G" \
  's|if (cap == 0) revert MarketNotConfigured(market);|if (cap == 0) cap = type(uint256).max;|' \
  'cap = type(uint256).max;'
mut "gross accounting drifts from parts" "$G" \
  's|gross = nextGross;|gross = nextGross - 1;|' \
  'gross = nextGross - 1;'
mut "reduce underflow guard removed" "$G" \
  's|if (amount > have) revert ReduceExceedsExposure(market, amount, have);||' \
  'exposureOf[market] = have - amount;'

echo
echo "=== mutations: OrderBookVenue ==="
mut "overfill guard removed" "$V" \
  's|if (baseAmount > rem) revert FillExceedsRemaining(baseAmount, rem);||' \
  'quoteAmount = (baseAmount * o.priceQuote) / 1e18;'
mut "fill accounting not recorded" "$V" \
  's|o.filledBase += baseAmount;|o.filledBase += 0;|' \
  'o.filledBase += 0;'
mut "price scale divisor dropped in take" "$V" \
  's|quoteAmount = (baseAmount \* o.priceQuote) / 1e18;|quoteAmount = (baseAmount * o.priceQuote);|' \
  'quoteAmount = (baseAmount * o.priceQuote);'
mut "sell escrow skipped at post" "$V" \
  's|IERC20Min(base).transferFrom(msg.sender, address(this), sizeBase);||' \
  'id = orders.length;'
# Sentinel must be a string that exists ONLY after the mutation, otherwise the
# grep check passes on the unmutated file and the result is meaningless.
mut "cancel refund skipped" "$V" \
  's|IERC20Min(o.base).transfer(o.maker, refundBase);|// MUTATED_NO_REFUND|' \
  'MUTATED_NO_REFUND'
mut "only-maker cancel check removed" "$V" \
  's|if (msg.sender != o.maker) revert NotMaker();||' \
  'if (o.cancelled) revert AlreadyCancelled();'

restore
echo
echo "=== restore check ==="
quiet && echo "restored GREEN" || { echo "RESTORE RED"; exit 1; }

{ echo; echo "## Summary"; echo; echo "- RED (good): $PASS"; echo "- gaps or inconclusive: $FAIL"; } >> "$OUT"
echo
echo "RED (good): $PASS   gaps: $FAIL"
echo "written: $OUT"
