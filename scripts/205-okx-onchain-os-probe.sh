#!/usr/bin/env bash
# Is the OKX ONCHAIN OS DEX API reachable, and does it serve X Layer (chain 196)?
#
# THIS IS NOT THE EXCHANGE OS PROBE. docs/verified/exchangeos-mainnet.md established that Exchange
# OS has no developer surface. Onchain OS is a different product: a REST DEX aggregator with public
# quote and market endpoints. It was never tested here, because the earlier probe used plain curl
# and got 000, which is DNS non-resolution under E9, not an answer from OKX.
#
# E9 says okx.com is blocked by this machine's resolver and must be reached with `curl --resolve`.
# scripts/04-exchangeos-surface.sh already pins web3.okx.com to 172.64.144.82 that way. Same route
# here, so a 000 means the host really is unreachable rather than that DNS failed.
#
# EVIDENCE PATH: evidence/phase19/okx-onchain-os.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase19/okx-onchain-os.txt"
mkdir -p "$(dirname "$OUT")"

PIN="--resolve web3.okx.com:443:172.64.144.82 --resolve www.okx.com:443:172.64.144.82"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36'

probe() { # label url
  local code body
  body=$(curl -sS --max-time 30 $PIN -A "$UA" -w '\n%{http_code}' "$2" 2>&1)
  code=$(printf '%s' "$body" | tail -1)
  printf "  %-58s %s\n" "$1" "$code"
  printf '%s' "$body" | head -c 400 | sed 's/^/      /'
  echo
}

{
echo "OKX Onchain OS reachability probe"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "DNS pinned per E9. A 000 here means the HOST is unreachable, not that DNS failed."
echo

echo "=== 1. supported chains ==="
probe "dex/aggregator/supported/chain" \
  "https://web3.okx.com/api/v5/dex/aggregator/supported/chain"

echo "=== 2. tokens on chain 196 ==="
probe "dex/aggregator/all-tokens?chainId=196" \
  "https://web3.okx.com/api/v5/dex/aggregator/all-tokens?chainId=196"

echo "=== 3. a real quote on 196: 1 WOKB -> USDT ==="
probe "dex/aggregator/quote chain 196" \
  "https://web3.okx.com/api/v5/dex/aggregator/quote?chainId=196&amount=1000000000000000000&fromTokenAddress=0xe538905cf8410324e03a5a23c1c177a474d59b2b&toTokenAddress=0x1e4a5963abfd975d8c9021ce480b42188849d41d"

echo "=== 4. market price endpoint ==="
probe "dex/market/price chain 196" \
  "https://web3.okx.com/api/v5/dex/market/price?chainIndex=196&tokenContractAddress=0xe538905cf8410324e03a5a23c1c177a474d59b2b"

echo
echo "=== verdict ==="
echo "A 200 with JSON on any of the above means real market data is reachable and the agent"
echo "can source signals from it. A 401/403 means the endpoint exists but needs API credentials."
echo "A 000 means unreachable from here even with DNS pinned."
} 2>&1 | tee "$OUT"
