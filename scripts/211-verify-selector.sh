#!/usr/bin/env bash
# Verify the maxDivergenceBps() selector and read the live value off mainnet.
#
# WHY A SCRIPT FILE. CLAUDE.md E4: parentheses passed through `wsl -- bash -c` are mangled by the
# invoking shell, and `cast sig "maxDivergenceBps()"` is exactly that shape. This has bitten
# repeatedly; the rule is script files, not inline commands.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

export PATH="$PATH:$HOME/.foundry/bin"

GUARD=$(python3 -c "import json;print(json.load(open('$REPO/deployments-mainnet.json'))['rwaRiskGuard'])")
RPC=$(python3 -c "import json;print(json.load(open('$REPO/deployments-mainnet.json'))['rpc'])")

SEL=$(cast sig "maxDivergenceBps()")
echo "selector    $SEL"
echo "guard       $GUARD"

RAW=$(cast call "$GUARD" "maxDivergenceBps()" --rpc-url "$RPC" 2>&1)
echo "raw         $RAW"
echo "decimal     $(python3 -c "print(int('$RAW', 16))" 2>/dev/null || echo 'not a number')"
