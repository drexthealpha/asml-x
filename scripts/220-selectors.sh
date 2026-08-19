#!/usr/bin/env bash
# Every function selector the frontend encodes, computed by `cast sig` rather than guessed.
#
# WHY THIS SCRIPT EXISTS. A selector invented rather than derived has already cost this project
# once: `maxDivergenceBps()` was written as 0xd8f6bef5, the real value is 0xf9de4776, and the wrong
# one made every eth_call return 0x while the code fell back to a remembered number and the screen
# said "read from the chain". A wrong selector never errors, it just silently returns nothing.
#
# The frontend hand-encodes calldata (no ABI bundle, no ethers), so every selector it uses is
# checked here and the output is pasted into src/lib/wallet.ts.
set -uo pipefail
cd "$(dirname "$0")/../contracts"
export PATH="$HOME/.foundry/bin:$PATH"

for s in \
  "deposit(uint256,uint256)" \
  "withdraw(uint256)" \
  "withdrawAll()" \
  "maxNotional(address)" \
  "balanceOf(address)" \
  "decimals()" \
  "paused()" \
  "approve(address,uint256)" \
  "allowance(address,address)"
do
  printf "%-34s %s\n" "$s" "$(cast sig "$s")"
done
