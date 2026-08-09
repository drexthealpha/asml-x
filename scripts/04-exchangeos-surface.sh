#!/usr/bin/env bash
# Task 0.3.2 / 0.3.3: does Exchange OS expose ANY reachable developer surface on
# testnet? Probes candidate TradeZone RPC hosts and enumerates the docs nav.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
WORK="$REPO/evidence/exchangeos-recon"
mkdir -p "$WORK"

probe_rpc() {
  printf '%-46s ' "$1"
  R=$(curl -sS --max-time 10 -X POST -H 'content-type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' "$1" 2>&1 | head -c 150)
  H=$(printf '%s' "$R" | grep -oE '0x[0-9a-fA-F]+' | head -1)
  if [ -n "$H" ]; then printf 'chainId %s = %d\n' "$H" "$H"
  else printf 'FAIL %s\n' "$(printf '%s' "$R" | tr -d '\n' | head -c 70)"; fi
}

echo "=== candidate TradeZone / Exchange OS endpoints ==="
probe_rpc https://tradezone-testrpc.xlayer.tech
probe_rpc https://testrpc-tradezone.xlayer.tech
probe_rpc https://tradezone.xlayer.tech
probe_rpc https://exchangeos-testrpc.xlayer.tech
probe_rpc https://tz-testrpc.xlayer.tech

echo
echo "=== docs nav: any Exchange OS developer section? ==="
curl -sS --max-time 60 --resolve web3.okx.com:443:172.64.144.82 -L -A "Mozilla/5.0 Chrome/126" \
  "https://web3.okx.com/onchainos/dev-docs/xlayer/developer/build-on-xlayer/about-xlayer" \
  > "$WORK/devdocs-nav.html" 2>/dev/null
printf 'nav bytes: %s\n' "$(wc -c < "$WORK/devdocs-nav.html")"
echo "-- occurrences of exchange/tradezone/venue/orderbook in the docs nav:"
grep -oiE '(exchange[ -]?os|tradezone|trade zone|order ?book|venue|perpetual|outcome market)' \
  "$WORK/devdocs-nav.html" | sort | uniq -c | sort -rn | head -15
echo "-- doc link paths mentioning those terms:"
grep -oE '"link":"[^"]*"' "$WORK/devdocs-nav.html" \
  | grep -iE 'exchange|trade|venue|order|perp|outcome' | sort -u | head -20

echo
echo "=== status page: which environments does X Layer report? ==="
curl -sS --max-time 40 -L -A "Mozilla/5.0 Chrome/126" "https://status.xlayer.tech" 2>/dev/null \
  | sed -e 's/<[^>]*>/ /g' | tr -s ' \n' ' \n' | grep -oiE '.{0,60}(testnet|mainnet|tradezone|exchange).{0,60}' | head -12
