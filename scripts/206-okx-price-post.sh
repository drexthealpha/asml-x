#!/usr/bin/env bash
# Can we get REAL X Layer market prices from OKX Onchain OS with NO API key?
#
# 205 established the host is reachable and the aggregator endpoints demand OK-ACCESS-KEY. But
# dex/market/price answered 200 with "Request method 'GET' not supported", which is a routing
# answer, not an auth rejection. If it serves POST without credentials, the agent can source live
# prices for chain 196 at zero cost and with no key to manage.
#
# EVIDENCE PATH: evidence/phase19/okx-price.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase19/okx-price.txt"
mkdir -p "$(dirname "$OUT")"

PIN="--resolve web3.okx.com:443:172.64.144.82 --resolve www.okx.com:443:172.64.144.82"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36'
WOKB=0xe538905cf8410324e03a5a23c1c177a474d59b2b

post() { # label url json
  local body code
  body=$(curl -sS --max-time 30 $PIN -A "$UA" \
    -H 'content-type: application/json' \
    -X POST -d "$3" -w '\n%{http_code}' "$2" 2>&1)
  code=$(printf '%s' "$body" | tail -1)
  printf "  %-46s %s\n" "$1" "$code"
  printf '%s' "$body" | head -c 500 | sed 's/^/      /'
  echo; echo
}

get() { # label url
  local body code
  body=$(curl -sS --max-time 30 $PIN -A "$UA" -w '\n%{http_code}' "$2" 2>&1)
  code=$(printf '%s' "$body" | tail -1)
  printf "  %-46s %s\n" "$1" "$code"
  printf '%s' "$body" | head -c 500 | sed 's/^/      /'
  echo; echo
}

{
echo "OKX Onchain OS market data, keyless probe"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

echo "=== POST dex/market/price, chain 196 WOKB ==="
post "market/price" "https://web3.okx.com/api/v5/dex/market/price" \
  "[{\"chainIndex\":\"196\",\"tokenContractAddress\":\"$WOKB\"}]"

echo "=== POST dex/market/price, native OKB (zero address) ==="
post "market/price native" "https://web3.okx.com/api/v5/dex/market/price" \
  "[{\"chainIndex\":\"196\",\"tokenContractAddress\":\"\"}]"

echo "=== public OKX ticker for OKB-USDT (no key on v5 market endpoints) ==="
get "market/ticker OKB-USDT" \
  "https://www.okx.com/api/v5/market/ticker?instId=OKB-USDT"

echo "=== public OKX candles, for a real price series ==="
get "market/candles OKB-USDT 1m" \
  "https://www.okx.com/api/v5/market/candles?instId=OKB-USDT&bar=1m&limit=3"

echo "=== public index price ==="
get "market/index-tickers BTC-USD" \
  "https://www.okx.com/api/v5/market/index-tickers?instId=BTC-USD"
} 2>&1 | tee "$OUT"
