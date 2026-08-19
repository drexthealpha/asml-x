#!/usr/bin/env bash
# Probe every Onchain OS surface once, and record which ones answer.
#
# A SCRIPT FILE because CLAUDE.md E4: `$VAR` and `$(...)` are stripped when passed through
# `wsl -- bash -c`, so an inline probe silently sent an empty address and the CLI reported a
# missing argument for one that had been supplied. That has now bitten twelve times.
#
# EVIDENCE PATH: evidence/phase20/oos-surfaces.txt
set -uo pipefail
cd "$(dirname "$0")"

WOKB="0xe538905cf8410324e03a5a23c1c177a474d59b2b"
USDT="0x779ded0c9e1022225f8e0630b35a9b54be713736"
DEPLOYER="0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46"
OUT="../evidence/phase20/oos-surfaces.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

probe() {
  local label="$1"; shift
  printf '%-34s ' "$label"
  local raw
  raw="$(bash oos.sh "$@" < /dev/null 2>&1 | tail -c 3000)"
  # The CLI prints progress lines before its JSON, so parse from the first brace.
  python3 - "$raw" <<'PY'
import json, sys
raw = sys.argv[1]
i = raw.find("{")
if i < 0:
    print("NO JSON")
    raise SystemExit
try:
    d = json.loads(raw[i:])
except Exception:
    print("UNPARSEABLE")
    raise SystemExit
if not d.get("ok"):
    print("FAIL", str(d.get("error"))[:70])
    raise SystemExit
data = d.get("data")
if isinstance(data, list):
    print(f"OK  {len(data)} rows")
elif isinstance(data, dict):
    keys = ", ".join(list(data.keys())[:6])
    print(f"OK  {keys}")
else:
    print("OK")
PY
}

echo "=== MARKET ==="
probe "market price"            --chain xlayer market price --address "$WOKB"
probe "market index"            --chain xlayer market index --address "$WOKB"
probe "market kline"            --chain xlayer market kline --address "$WOKB"
probe "portfolio-overview"      --chain xlayer market portfolio-overview --address "$DEPLOYER"
probe "portfolio-dex-history"   --chain xlayer market portfolio-dex-history --address "$DEPLOYER"

echo
echo "=== TOKEN ==="
probe "token info"              --chain xlayer token info --address "$WOKB"
probe "token price-info"        --chain xlayer token price-info --address "$WOKB"
probe "token liquidity"         --chain xlayer token liquidity --address "$WOKB"
probe "token holders"           --chain xlayer token holders --address "$WOKB"
probe "token advanced-info"     --chain xlayer token advanced-info --address "$WOKB"
probe "token hot-tokens"        --chain xlayer token hot-tokens

echo
echo "=== SECURITY ==="
probe "security token-scan"     --chain xlayer security token-scan --tokens "196:$WOKB"
probe "security approvals"      --chain xlayer security approvals --address "$DEPLOYER"

echo
echo "=== SIGNAL / SOCIAL ==="
probe "signal chains"           signal chains
probe "signal list"             --chain xlayer signal list
probe "social news"             social --help

echo
echo "=== DEFI ==="
probe "defi support-chains"     defi support-chains
probe "defi search earn"        defi search --chain xlayer --token USDT,USDC,OKB
probe "defi search lending"     defi search --chain xlayer --token USDT --product-group LENDING

echo
echo "=== SWAP ==="
probe "swap quote"              --chain xlayer swap quote --from "$WOKB" --to "$USDT" --readable-amount 1

echo
echo "=== WALLET (needs login) ==="
probe "wallet status"           wallet status
probe "wallet chains"           wallet chains
