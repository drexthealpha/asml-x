#!/usr/bin/env bash
# Can the agent trade using OKB, which the deployer ALREADY HOLDS, instead of USDT it does not?
#
# WHY THIS IS THE BETTER ASSET, and it was a miss not to start here. USDT was chosen as the vault's
# accounting asset, so USDT became the assumed input to every swap. But OKB is X Layer's native
# token, the deployer holds it for gas already, and WOKB (its ERC20 wrapper) is the DEEPEST pair on
# the chain by the measurement this project already made: scripts/okx_depth.py found WOKB/USDT
# holds inside 100 bps up to 100 WOKB across eight venues. Requiring USDT meant asking for funding
# that the OKB path does not need at all.
#
# WHAT THIS CHECKS, read-only, spends nothing:
#   1. WOKB really is a wrapper with a payable deposit(), so OKB converts 1:1 without a trade
#   2. the aggregator will still quote a TINY size, because the whole balance available is small
#   3. what the round trip actually costs at that size
#
# A real swap of 0.002 WOKB is exactly as real as one of 1000. Size proves nothing about realness.
#
# EVIDENCE PATH: evidence/phase19/okb-path.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.foundry/bin:$PATH"

RPC="https://rpc.xlayer.tech"
OUT="$REPO/evidence/phase19/okb-path.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

WOKB=$(python3 -c "import tokens;print(tokens.address('WOKB'))") || exit 1
echo "WOKB, discovered      $WOKB"
echo "symbol, from contract $(cast call "$WOKB" 'symbol()(string)' --rpc-url "$RPC" 2>/dev/null)"
echo "decimals              $(cast call "$WOKB" 'decimals()(uint8)' --rpc-url "$RPC" 2>/dev/null)"

# A WETH-style wrapper exposes a payable deposit(). If this selector is absent, wrapping needs a
# different route and that has to be known BEFORE anything is signed.
echo -n "has deposit()         "
if cast call "$WOKB" 'deposit()' --value 0 --rpc-url "$RPC" >/dev/null 2>&1; then
  echo "yes, OKB wraps 1:1"
else
  echo "NOT a plain wrapper, wrapping needs another route"
fi

echo
echo "=== balances ==="
BAL=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
echo "deployer OKB          $(python3 -c "print(int('$BAL')/1e18)")"
EXEC=$(python3 -c "import json;print(json.load(open('$REPO/deployments-mainnet.json'))['routerExecutor'])")
echo "executor              $EXEC"
echo "executor WOKB         $(cast call "$WOKB" 'balanceOf(address)(uint256)' "$EXEC" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')"

echo
echo "=== will the aggregator quote a tiny size? ==="
for SIZE in 0.001 0.002 0.01; do
  echo -n "  $SIZE WOKB -> USDT: "
  if Q=$(python3 swap_calldata.py WOKB USDT "$SIZE" "$EXEC" 2>&1); then
    echo "$Q" | python3 -c "import json,sys;d=json.load(sys.stdin);print(f\"min receive {d['min_receive']} via {', '.join(d['venues'])}\")"
  else
    echo "declined: $(echo "$Q" | head -c 90)"
  fi
done
