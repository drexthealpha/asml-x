#!/usr/bin/env bash
# One selector, and its live value. E4 again: `cast sig "committed(address)"` inline through
# `wsl -- bash -c` puts the Windows PATH with "Program Files (x86)" on the command line and the
# unquoted parentheses are a syntax error before anything runs.
set -uo pipefail
cd "$(dirname "$0")/../contracts"
export PATH="$HOME/.foundry/bin:$PATH"

RPC="https://rpc.xlayer.tech"
VAULT=$(python3 -c "import json;print(json.load(open('../deployments-mainnet.json'))['agentVault'])")
ME="0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46"

SIG=$(cast sig "committed(address)")
VAL=$(cast call "$VAULT" "committed(address)(uint256)" "$ME" --rpc-url "$RPC" 2>/dev/null || echo revert)
printf 'committed(address)  %s  -> %s\n' "$SIG" "$VAL"
