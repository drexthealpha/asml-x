#!/usr/bin/env bash
# GATE: no hardcoded market data anywhere in the frontend.
#
# WHY THIS IS A CI GATE AND NOT A CONVENTION. "No hardcoded data" has been asserted in this project
# more than once and has been wrong more than once: a literal free-margin of 1_000 units, a typed
# USDT address, an invented function selector, a remembered 300 bps limit. Each was believed to be
# fine until someone looked. A rule nobody can violate is worth more than a rule everyone agrees
# with, so this fails the build.
#
# WHAT COUNTS AS A VIOLATION:
#   - a token contract address written as a literal (they are discovered from the chain)
#   - a price, balance, APY, TVL or holder count assigned as a literal
#   - a chain-196 explorer URL with an address baked into it
#
# WHAT IS DELIBERATELY ALLOWED, and why each is not data:
#   - colours (#3b82f6)                design tokens from the spec
#   - poll intervals (4000)            configuration, not measurement
#   - chain id 196 and the RPC         the network the product targets
#   - function selectors (0x70a08231)  computed by `cast sig`, verified in scripts/220
#   - the WalletConnect project id     a public client identifier
#
# EVIDENCE PATH: evidence/phase20/no-hardcoded-data.txt
set -uo pipefail
cd "$(dirname "$0")/.."

SRC="ui-v2/src"
OUT="evidence/phase20/no-hardcoded-data.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

FAIL=0

echo "=== 1. token contract addresses as literals ==="
# 40-hex addresses. Selectors are 8 hex and do not match. The wallet's chain config holds no token
# address, so any hit here is a token address someone typed.
HITS=$(grep -rnE "0x[a-fA-F0-9]{40}" --include='*.ts' --include='*.tsx' "$SRC" || true)
if [ -n "$HITS" ]; then
  echo "$HITS"
  FAIL=1
else
  echo "  none"
fi

echo
echo "=== 2. market values assigned as literals ==="
HITS=$(grep -rnE "\b(price|balance|apy|tvl|holders|liquidity|marketCap|volume|supply)\b[[:space:]]*[:=][[:space:]]*[\"']?[0-9]" \
  --include='*.ts' --include='*.tsx' "$SRC" \
  | grep -viE "poll|interval|timeout|width|height|size=|fontSize|strokeWidth|maxAmountRequired" || true)
if [ -n "$HITS" ]; then
  echo "$HITS"
  FAIL=1
else
  echo "  none"
fi

echo
echo "=== 3. explorer URLs with an address baked in ==="
HITS=$(grep -rnE "oklink\.com[^\"']*0x[a-fA-F0-9]{6,}" --include='*.ts' --include='*.tsx' "$SRC" || true)
if [ -n "$HITS" ]; then
  echo "$HITS"
  FAIL=1
else
  echo "  none"
fi

echo
echo "=== 4. every constant in the frontend, for the record ==="
grep -rnE "^const [A-Z_]+ =" --include='*.ts' --include='*.tsx' "$SRC" || echo "  none"

echo
echo "=== 5. the data files the UI reads are generated, not committed by hand ==="
for f in universe market rwa depth onchainos intel detail activity; do
  p="ui-v2/public/data/$f.json"
  if [ -f "$p" ]; then
    SRCLINE=$(python3 -c "
import json,sys
try:
    d=json.load(open('$p'))
    print(d.get('source') or d.get('generatedBy') or 'NO SOURCE FIELD')
except Exception as e:
    print('unreadable:', e)
" 2>/dev/null)
    printf '  %-12s %s\n' "$f" "$SRCLINE"
    case "$SRCLINE" in
      "NO SOURCE FIELD"|unreadable*)
        # A data file with no provenance is indistinguishable from one somebody typed.
        FAIL=1
        ;;
    esac
  fi
done

echo
if [ "$FAIL" -ne 0 ]; then
  echo "GATE: FAIL — hardcoded data reached the frontend"
  exit 1
fi
echo "GATE: PASS — no hardcoded market data in the frontend"
