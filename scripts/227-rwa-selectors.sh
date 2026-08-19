#!/usr/bin/env bash
# Compute the RWA contract selectors with `cast sig`, then read each value off mainnet.
#
# WHY: an invented selector has already cost this project real time once. `maxDivergenceBps()` was
# written as 0xd8f6bef5 from memory; the real value is 0xf9de4776. A wrong selector does not error,
# `eth_call` returns 0x, the code falls back to a remembered number, and the screen says "read from
# the chain" while nothing was read. This script is how that stops being possible.
set -uo pipefail
cd "$(dirname "$0")/../contracts"
export PATH="$HOME/.foundry/bin:$PATH"

RPC="https://rpc.xlayer.tech"
GUARD=$(python3 -c "import json;print(json.load(open('../deployments-mainnet.json'))['rwaRiskGuard'])")
VAULT=$(python3 -c "import json;print(json.load(open('../deployments-mainnet.json'))['rwaVault'])")
OUT="../evidence/phase20/rwa-selectors.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

echo "guard $GUARD"
echo "vault $VAULT"
echo

for s in "maxDivergenceBps()" "maxOracleAge()" "windowBufferSeconds()" "owner()" "paused()" "asset()"; do
  SIG=$(cast sig "$s")
  VAL=$(cast call "$GUARD" "$s" --rpc-url "$RPC" 2>/dev/null || echo "revert")
  printf '%-26s %s  guard -> %s\n' "$s" "$SIG" "${VAL:-0x}"
done

echo
echo "--- vault ---"
for s in "paused()" "asset()" "owner()"; do
  VAL=$(cast call "$VAULT" "$s" --rpc-url "$RPC" 2>/dev/null || echo "revert")
  printf '%-26s vault -> %s\n' "$s" "${VAL:-0x}"
done
