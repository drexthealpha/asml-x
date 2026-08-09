#!/usr/bin/env bash
# Task 1.3 groundwork under the hybrid decision: what is ACTUALLY deployed on
# chain 1952? Probes canonical addresses for bytecode. Deterministic-deploy
# infrastructure lands at the same address on every EVM chain, so presence or
# absence here is hard evidence, not a guess.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
DOCS="$REPO/docs/verified"
mkdir -p "$DOCS"

RPC="$XLAYER_TESTNET_RPC"

check() {
  # $1 = address, $2 = label
  SIZE=$(cast code "$1" --rpc-url "$RPC" 2>/dev/null | wc -c)
  # "0x" plus newline = 3 chars when there is no code
  if [ "$SIZE" -gt 4 ]; then
    printf 'PRESENT  %-44s %-34s bytecode_chars=%s\n' "$2" "$1" "$SIZE"
  else
    printf 'absent   %-44s %-34s\n' "$2" "$1"
  fi
}

echo "=== canonical cross-chain infrastructure on chain 1952 ==="
check 0xcA11bde05977b3631167028862bE2a173976CA11 "Multicall3"
check 0x000000000022D473030F116dDEE9F6B43aC78BA3 "Permit2"
check 0x4e59b44847b379578588920cA78FbF26c0B4956C "CREATE2 deterministic deployer"
check 0x1F98431c8aD98523631AE4a59f267346ea31F984 "Uniswap V3 Factory (canonical)"
check 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f "Uniswap V2 Factory (canonical)"
check 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45 "Uniswap V3 SwapRouter02"
check 0xC36442b4a4522E871399CD717aBDD847Ab11FE88 "Uniswap V3 NFT Position Manager"
check 0x0000000000FFe8B47B3e2130213B802212439497 "UniswapX / other"
check 0x00000000000001ad428e4906aE43D8F9852d0dD6 "Seaport 1.4"
check 0x4200000000000000000000000000000000000006 "OP-stack WETH predeploy"
check 0x4200000000000000000000000000000000000010 "OP-stack L2StandardBridge"
check 0x4200000000000000000000000000000000000011 "OP-stack SequencerFeeVault"
check 0x4200000000000000000000000000000000000015 "OP-stack L1Block"
check 0x4200000000000000000000000000000000000016 "OP-stack L2ToL1MessagePasser"

echo
echo "=== is this chain OP-stack predeploy shaped? (settles the V2 question) ==="
echo "L1Block.number() ->"
cast call 0x4200000000000000000000000000000000000015 "number()(uint64)" --rpc-url "$RPC" 2>&1 | head -2

echo
echo "=== native currency + block shape ==="
cast rpc eth_getBlockByNumber latest false --rpc-url "$RPC" 2>/dev/null \
  | python3 -c "
import json,sys
b=json.load(sys.stdin)
for k in ['number','timestamp','gasLimit','gasUsed','baseFeePerGas','miner','extraData']:
    v=b.get(k)
    if v is None: continue
    try: dec=int(v,16)
    except Exception: dec=v
    print(f'{k:16} {v}  ({dec})')
print('tx_count        ', len(b.get('transactions',[])))
"

echo
echo "=== two consecutive block timestamps (real block time) ==="
cast rpc eth_getBlockByNumber latest false --rpc-url "$RPC" 2>/dev/null | python3 -c "
import json,sys; b=json.load(sys.stdin); print('latest ts', int(b['timestamp'],16), 'num', int(b['number'],16))"
sleep 5
cast rpc eth_getBlockByNumber latest false --rpc-url "$RPC" 2>/dev/null | python3 -c "
import json,sys; b=json.load(sys.stdin); print('latest ts', int(b['timestamp'],16), 'num', int(b['number'],16))"
