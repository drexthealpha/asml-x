#!/usr/bin/env bash
# The REAL error selectors, and how a depositor's pause state is actually read.
#
# TWO CORRECTIONS THIS RECORDS.
#
# 1. The errors carry PARAMETERS. `ExceedsUserLimit(uint256,uint256)` is not
#    `ExceedsUserLimit()`, and the selectors differ completely. A UI decoding the parameterless
#    form matches nothing and falls back to showing raw hex to someone whose transaction just
#    failed, at the exact moment they most need a sentence they can act on.
#
# 2. `paused()` REVERTS on AgentVault. There is no global pause: the contract has
#    `DepositorPaused(address)`, so pause is PER DEPOSITOR. Every earlier read of `paused()` was
#    returning nothing and being rendered as "not paused", which is a safety claim nobody checked.
#
# EVIDENCE PATH: evidence/phase21/vault-errors.txt
set -uo pipefail
cd "$(dirname "$0")/../contracts"
export PATH="$HOME/.foundry/bin:$PATH"

OUT="../evidence/phase21/vault-errors.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

RPC="https://rpc.xlayer.tech"
VAULT=$(python3 -c "import json;print(json.load(open('../deployments-mainnet.json'))['agentVault'])")
ME="0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46"

echo "=== error selectors, with their real signatures ==="
for e in \
  "ZeroAmount()" \
  "ZeroAddress()" \
  "NotAgent()" \
  "NotOwner()" \
  "Reentrancy()" \
  "TransferFailed()" \
  "NothingCommitted()" \
  "DepositorPaused(address)" \
  "ExceedsUserLimit(uint256,uint256)" \
  "InsufficientBalance(uint256,uint256)" \
  "ShortDeposit(uint256,uint256)"
do
  printf '  %-40s %s\n' "$e" "$(cast sig "$e")"
done

echo
echo "=== how pause is actually stored, from the source ==="
grep -nE "paused|Paused" src/AgentVault.sol | grep -vE "^\s*//|\*" | head -12

echo
echo "=== every public mapping and variable ==="
grep -oE "mapping\([^)]*\) public [a-zA-Z0-9_]+|uint256 public [a-zA-Z0-9_]+|bool public [a-zA-Z0-9_]+|address public [a-zA-Z0-9_]+" src/AgentVault.sol | sed 's/^/  /'

echo
echo "=== live values for the deployer ==="
for s in "maxNotional(address)(uint256)" "balanceOf(address)(uint256)" "paused(address)(bool)"; do
  VAL=$(cast call "$VAULT" "$s" "$ME" --rpc-url "$RPC" 2>/dev/null || echo "revert or absent")
  printf '  %-34s %s\n' "$s" "$VAL"
done
