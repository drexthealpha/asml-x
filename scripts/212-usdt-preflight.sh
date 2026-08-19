#!/usr/bin/env bash
# Preflight before redeploying the vault against REAL USDT on X Layer mainnet.
#
# WHY A PREFLIGHT AND NOT JUST A DEPLOY. The vault is being pointed at a token this project does
# not control, on a chain where a mistake costs real money and cannot be undone. Three things have
# to be true first, and each one is a different failure if it is not:
#
#   1. The USDT address must come from the CHAIN's token list, not from memory. A vault deployed
#      against a wrong or bridged-variant address would accept deposits of a token nobody wants.
#   2. Its decimals must be READ. USDT is 6 decimals on most chains and the entire existing UI
#      formats balances by dividing by 1e18. If that is not corrected the product will display a
#      real 10 USDT deposit as 0.00000000000001, which looks like the money vanished.
#   3. The deployer must actually hold gas. A deploy that runs out mid-sequence leaves a partially
#      wired system on mainnet, which is worse than not starting.
#
# This script only READS. It sends no transaction and spends nothing.
#
# EVIDENCE PATH: evidence/phase19/usdt-preflight.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

export PATH="$PATH:$HOME/.foundry/bin"
RPC="https://rpc.xlayer.tech"
OUT="$REPO/evidence/phase19/usdt-preflight.txt"
mkdir -p "$(dirname "$OUT")"

exec > >(tee "$OUT") 2>&1

echo "=== chain ==="
CHAIN=$(python3 -c "print(int('$(cast rpc eth_chainId --rpc-url "$RPC" | tr -d '\"')', 16))")
echo "chain id                 $CHAIN"
[ "$CHAIN" = "196" ] || { echo "ABORT: not chain 196"; exit 1; }

echo
echo "=== USDT, resolved from the chain's own token list ==="
USDT=$(python3 usdt_addr.py) || { echo "ABORT: could not resolve USDT from Onchain OS"; exit 1; }
echo "address                  $USDT"

SYM=$(cast call "$USDT" "symbol()(string)" --rpc-url "$RPC" 2>/dev/null)
DEC=$(cast call "$USDT" "decimals()(uint8)" --rpc-url "$RPC" 2>/dev/null)
SUP=$(cast call "$USDT" "totalSupply()(uint256)" --rpc-url "$RPC" 2>/dev/null)
echo "symbol, from contract    $SYM"
echo "decimals, from contract  $DEC"
echo "total supply             $SUP"

echo
echo "=== deployer ==="
echo "address                  $DEPLOYER_ADDRESS"
BAL=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>/dev/null)
echo "OKB for gas, wei         $BAL"
echo "OKB for gas              $(python3 -c "print(int('$BAL')/1e18)" 2>/dev/null)"

UBAL=$(cast call "$USDT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
echo "USDT held, raw           $UBAL"
echo "USDT held                $(python3 -c "print(int('$UBAL')/10**int('$DEC'))" 2>/dev/null)"

echo
echo "=== what this means ==="
echo "The vault credits the MEASURED balance delta, so it needs no decimals constant itself."
echo "The UI does: formatWei divides by 1e18 everywhere and must be made decimals-aware before"
echo "any real deposit is displayed, or a real balance will render as a rounding error."
