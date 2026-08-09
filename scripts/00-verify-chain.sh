#!/usr/bin/env bash
# Task 0.2.4 - 0.2.6: prove the chain is real, reachable, and the wallet is funded.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
load_all_creds

echo "=== credentials (presence only) ==="
cred_status

echo
echo "=== toolchain ==="
printf 'cast   %s\n' "$(cast --version 2>/dev/null | head -1)"
printf 'forge  %s\n' "$(forge --version 2>/dev/null | head -1)"

echo
echo "=== X Layer testnet (task 0.2.4, 0.2.5) ==="
printf 'rpc            %s\n' "$XLAYER_TESTNET_RPC"
printf 'chain_id       %s (expect %s)\n' "$(cast chain-id --rpc-url "$XLAYER_TESTNET_RPC")" "$XLAYER_TESTNET_CHAIN_ID"
B1=$(cast block-number --rpc-url "$XLAYER_TESTNET_RPC")
printf 'block_number   %s\n' "$B1"
printf 'gas_price_wei  %s\n' "$(cast gas-price --rpc-url "$XLAYER_TESTNET_RPC")"

echo
echo "=== deployer wallet (task 0.2.6) ==="
printf 'address        %s\n' "$DEPLOYER_ADDRESS"
printf 'balance_okb    %s\n' "$(cast balance --ether "$DEPLOYER_ADDRESS" --rpc-url "$XLAYER_TESTNET_RPC")"
printf 'nonce          %s\n' "$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$XLAYER_TESTNET_RPC")"

echo
echo "=== observed block time (task 0.2.5, real not marketing) ==="
sleep 12
B2=$(cast block-number --rpc-url "$XLAYER_TESTNET_RPC")
printf 'blocks in 12s  %s (from %s to %s)\n' "$((B2-B1))" "$B1" "$B2"

echo
echo "=== fallback rpc ==="
printf 'fallback chain_id %s\n' "$(cast chain-id --rpc-url "$XLAYER_TESTNET_RPC_FALLBACK" 2>&1 | head -1)"
