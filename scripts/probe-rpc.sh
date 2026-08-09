#!/usr/bin/env bash
# Probes candidate X Layer RPC endpoints for eth_chainId.
# Written as a file because passing $vars through `wsl -- bash -c` strips them (E4).
probe() {
  printf "%-40s " "$1"
  RESP=$(curl -sS --max-time 12 -X POST -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' "$1" 2>&1 | head -c 200)
  HEX=$(printf '%s' "$RESP" | grep -oE '0x[0-9a-fA-F]+' | head -1)
  if [ -n "$HEX" ]; then
    printf 'chainId %s = %d\n' "$HEX" "$HEX"
  else
    printf 'FAIL %s\n' "$(printf '%s' "$RESP" | tr -d '\n' | head -c 90)"
  fi
}

probe https://testrpc.xlayer.tech
probe https://xlayertestrpc.okx.com
probe https://x1testrpc.okx.com
probe https://rpc.xlayer.tech
probe https://xlayer-testnet.drpc.org
probe https://195.rpc.thirdweb.com
probe https://1952.rpc.thirdweb.com
probe https://xlayer-sepolia.drpc.org
probe https://testnet-rpc.xlayer.tech
