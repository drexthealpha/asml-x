#!/usr/bin/env bash
# Task 1 and 2: every WRITE selector the limit control and vault surface need.
#
# Computed with `cast sig`, never written from memory. A wrong write selector does not revert
# helpfully: it hits the fallback or a different function, and the user signs a transaction that
# does something other than what the button said. That is worse than the read-path failures this
# project has already had, because it costs gas and can move money.
#
# EVIDENCE PATH: evidence/phase21/vault-write-selectors.txt
set -uo pipefail
cd "$(dirname "$0")/../contracts"
export PATH="$HOME/.foundry/bin:$PATH"

OUT="../evidence/phase21/vault-write-selectors.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

RPC="https://rpc.xlayer.tech"
VAULT=$(python3 -c "import json;print(json.load(open('../deployments-mainnet.json'))['agentVault'])")
GUARD=$(python3 -c "import json;print(json.load(open('../deployments-mainnet.json'))['riskGuard'])")

echo "AgentVault $VAULT"
echo
echo "=== writes ==="
for s in \
  "deposit(uint256,uint256)" \
  "withdraw(uint256)" \
  "withdrawAll()" \
  "setMaxNotional(uint256)" \
  "setPaused(bool)" \
  "approve(address,uint256)"
do
  printf '  %-34s %s\n' "$s" "$(cast sig "$s")"
done

echo
echo "=== reads, each with its live value ==="
for s in "maxNotional(address)" "balanceOf(address)" "totalDeposits()" "totalCommitted()" "isSolvent()" "paused()" "asset()" "owner()"; do
  SIG=$(cast sig "$s")
  case "$s" in
    *"(address)")
      VAL=$(cast call "$VAULT" "$s(uint256)" "0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46" --rpc-url "$RPC" 2>/dev/null || echo revert) ;;
    *)
      VAL=$(cast call "$VAULT" "$s" --rpc-url "$RPC" 2>/dev/null || echo revert) ;;
  esac
  printf '  %-24s %s  -> %s\n' "$s" "$SIG" "${VAL:-0x}"
done

echo
echo "=== errors the UI must decode rather than show as hex ==="
for e in \
  "ZeroAmount()" "NotDepositor()" "InsufficientBalance()" "LimitCanOnlyTighten()" \
  "Paused()" "ReentrantCall()" "ZeroAddress()" "Insolvent()"
do
  printf '  %-28s %s\n' "$e" "$(cast sig "$e" 2>/dev/null || echo '(not in ABI)')"
done

echo
echo "=== the real error names in the contract source ==="
grep -oE "error [A-Za-z0-9_]+\([^)]*\)" src/AgentVault.sol | sort -u | sed 's/^/  /'
