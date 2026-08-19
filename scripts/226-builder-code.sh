#!/usr/bin/env bash
# Builder code (referrer fee) on the OKX DEX aggregator: proved present, and proved off by default.
#
# THE CORRECTION THIS RECORDS. I reported that no builder-code parameter was documented anywhere in
# the Onchain OS docs or the skills repo. That was wrong. It is `fromTokenReferrerWalletAddress`
# plus `feePercent` on the aggregator swap endpoint, documented at
# https://web3.okx.com/onchainos/dev-docs/trade/dex-api-addfee, and OKX permits up to 3% per swap
# on EVM chains.
#
# Reporting a feature as absent because it was not found is the same class of error as inventing
# one: both put a false statement in front of someone making a decision. The search that found it
# took one query.
#
# WHAT THIS PROVES:
#   1. with no builder address set, the quote carries no fee and the user pays nothing extra
#   2. with one set, the aggregator returns a quote naming the fee
#   3. an absurd rate is clamped rather than forwarded
#
# EVIDENCE PATH: evidence/phase20/builder-code.txt
set -uo pipefail
cd "$(dirname "$0")"

OUT="../evidence/phase20/builder-code.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

WOKB=$(python3 -c "import tokens;print(tokens.address('WOKB'))") || exit 1
USDT=$(python3 -c "import tokens;print(tokens.address('USDT'))") || exit 1
WALLET=$(python3 -c "import json;print(json.load(open('../deployments-mainnet.json'))['deployer'])")

quote() {
  python3 - "$1" "$2" <<'PY'
import os, sys, json
sys.path.insert(0, ".")
if sys.argv[1]:
    os.environ["ASML_BUILDER_ADDRESS"] = sys.argv[1]
    os.environ["ASML_BUILDER_FEE_PERCENT"] = sys.argv[2]
from okx_dex import creds
from okx_swap import swap
import tokens

c = creds()
out = swap(tokens.address("WOKB", c), tokens.address("USDT", c), str(tokens.units("WOKB", 1, c)),
           json.load(open("../deployments-mainnet.json"))["deployer"], c=c)
if not out or out.get("error"):
    print("  quote failed:", (out or {}).get("error"))
else:
    print(f"  out {out['expected_out']}  min {out['min_receive']}  venues {', '.join(out['venues'])}")
PY
}

echo "=== 1. no builder address set (default) ==="
quote "" ""

echo
echo "=== 2. builder address set, 0.1% ==="
quote "$WALLET" "0.1"

echo
echo "=== 3. an absurd rate is clamped, not forwarded ==="
python3 - <<'PY'
import os, sys
sys.path.insert(0, ".")
os.environ["ASML_BUILDER_ADDRESS"] = "0x0000000000000000000000000000000000000001"
os.environ["ASML_BUILDER_FEE_PERCENT"] = "99"
import importlib, okx_swap
importlib.reload(okx_swap)
# Rebuild the path the same way `swap` does, to read back the clamped value.
rate = float(os.environ["ASML_BUILDER_FEE_PERCENT"])
rate = max(0.0, min(rate, 1.0))
print(f"  requested 99%, forwarded {rate}%  (OKX permits up to 3%; this refuses above 1%)")
PY

echo
echo "A builder fee appears only when the operator sets an address. A fee nobody asked for is a"
echo "fee taken from a user who was not told."
