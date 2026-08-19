#!/usr/bin/env bash
# Which per-token detail endpoints actually return data, and what they contain.
#
# The detail view has to be built from fields that exist. Guessing them produced eleven blank rows
# once already (`tokenInfo` vs `token`), so every endpoint is called against a real token first and
# its top-level keys recorded.
#
# EVIDENCE PATH: evidence/phase20/token-detail.txt
set -uo pipefail
cd "$(dirname "$0")"

WOKB="0xe538905cf8410324e03a5a23c1c177a474d59b2b"
OUT="../evidence/phase20/token-detail.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

show() {
  local label="$1"; shift
  echo "=== $label"
  bash oos.sh "$@" < /dev/null 2>&1 | tail -c 2500 | python3 -c '
import json, sys
raw = sys.stdin.read()
i = raw.find("{")
if i < 0:
    print("  NO JSON"); raise SystemExit
try:
    d = json.loads(raw[i:])
except Exception:
    print("  truncated or unparseable"); raise SystemExit
if not d.get("ok"):
    print("  FAIL", str(d.get("error"))[:80]); raise SystemExit
data = d.get("data")
if isinstance(data, list):
    print(f"  {len(data)} rows")
    if data and isinstance(data[0], dict):
        for k, v in list(data[0].items())[:14]:
            print(f"    {k} = {str(v)[:60]}")
elif isinstance(data, dict):
    for k, v in list(data.items())[:14]:
        print(f"    {k} = {str(v)[:60]}")
'
  echo
}

show "token info"            --chain xlayer token info --address "$WOKB"
show "token price-info"      --chain xlayer token price-info --address "$WOKB"
show "token liquidity"       --chain xlayer token liquidity --address "$WOKB"
show "token advanced-info"   --chain xlayer token advanced-info --address "$WOKB"
show "token holders"         --chain xlayer token holders --address "$WOKB"
show "token top-trader"      --chain xlayer token top-trader --address "$WOKB"
show "token trades"          --chain xlayer token trades --address "$WOKB"
show "token cluster-overview" --chain xlayer token cluster-overview --address "$WOKB"
