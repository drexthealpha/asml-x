#!/usr/bin/env bash
# What is the FULL keyless surface? "Am I using every data point" deserves a measured answer.
#
# 205/206 established: web3.okx.com/api/v5/dex/* (Onchain OS aggregator) returns 401 without a key,
# and www.okx.com/api/v5/market/* is public. This enumerates the rest of the public market surface,
# because the agent currently uses only three of those endpoints and the to-do list asks for
# candidate generation from live BOOK DEPTH, which needs more than a top-of-book ticker.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase19/okx-full-surface.txt"
mkdir -p "$(dirname "$OUT")"
PIN="--resolve www.okx.com:443:172.64.144.82 --resolve web3.okx.com:443:172.64.144.82"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36'

try() { # label url
  local body code
  body=$(curl -sS --max-time 25 $PIN -A "$UA" -w '\n%{http_code}' "$2" 2>&1)
  code=$(printf '%s' "$body" | tail -1)
  printf "  %-34s %s\n" "$1" "$code"
  printf '%s' "$body" | head -c 260 | sed 's/^/      /'
  echo; echo
}

{
echo "OKX public surface enumeration"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

echo "=== order book DEPTH, 20 levels ==="
try "market/books OKB-USDT" "https://www.okx.com/api/v5/market/books?instId=OKB-USDT&sz=20"

echo "=== recent public trades, real flow ==="
try "market/trades OKB-USDT" "https://www.okx.com/api/v5/market/trades?instId=OKB-USDT&limit=5"

echo "=== instrument metadata: tick size, lot size, minimum ==="
try "public/instruments SPOT" "https://www.okx.com/api/v5/public/instruments?instType=SPOT&instId=OKB-USDT"

echo "=== index candles, a reference series for RWA divergence ==="
try "market/index-candles BTC-USD" "https://www.okx.com/api/v5/market/index-candles?instId=BTC-USD&bar=1m&limit=3"

echo "=== an RWA-shaped reference: gold and equity indices ==="
try "index-tickers XAUT-USD" "https://www.okx.com/api/v5/market/index-tickers?instId=XAUT-USD"
try "ticker PAXG-USDT" "https://www.okx.com/api/v5/market/ticker?instId=PAXG-USDT"

echo "=== 24h volume across the venue ==="
try "market/platform-24-volume" "https://www.okx.com/api/v5/market/platform-24-volume"
} 2>&1 | tee "$OUT"
