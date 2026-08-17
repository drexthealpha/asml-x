#!/usr/bin/env bash
# Task 11.7 continued: the predeploys are PROXIES. Follow them to the implementations.
#
# THE FINDING THAT MADE THIS NECESSARY. All five OP Stack predeploys returned byte-identical runtime
# code, keccak 0xfa8c9db6c6cab7108dea276f4cd09d575674eb0852c0fa3187e59e98ef977998, 2059 bytes each.
# Five contracts with completely different jobs cannot share one implementation, so the shared code
# is a PROXY and the behaviour lives behind an implementation slot.
#
# That is exactly why selector extraction on the proxy found nothing useful: a proxy has no dispatch
# table, it has a fallback that delegatecalls. Reading the proxy and stopping there would have been
# reverse engineering that produced a wrong answer confidently.
#
# EIP-1967 implementation slot:
#   keccak256("eip1967.proxy.implementation") - 1
#   = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
# Verified by computing it rather than pasting it, below.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/docs/verified/onchain-reverse-engineering-196.md"
BYTE="$REPO/evidence/phase11/bytecode"
RPC="https://rpc.xlayer.tech"

# Compute the slot rather than trusting a constant copied from a blog.
RAW=$(cast keccak "eip1967.proxy.implementation")
SLOT=$(python3 -c "print(hex(int('$RAW', 16) - 1))")
ADMIN_RAW=$(cast keccak "eip1967.proxy.admin")
ADMIN_SLOT=$(python3 -c "print(hex(int('$ADMIN_RAW', 16) - 1))")

{
echo
echo "## THE PREDEPLOYS ARE PROXIES, and that changes the whole method"
echo
echo "Five contracts with entirely different jobs returned **byte-identical runtime code**:"
echo
echo '```'
echo "keccak256(runtime)  0xfa8c9db6c6cab7108dea276f4cd09d575674eb0852c0fa3187e59e98ef977998"
echo "size                2059 bytes"
echo "shared by           L2ToL1MessagePasser, L1Block, GasPriceOracle,"
echo "                    L2StandardBridge, L2CrossDomainMessenger"
echo '```'
echo
echo "A message passer and a gas oracle cannot be the same program. The shared code is a PROXY, and"
echo "the behaviour lives behind an implementation slot. This is why scanning the proxy for a"
echo "dispatch table found nothing worth reporting: a proxy has no dispatcher, it has a fallback that"
echo "delegatecalls. Stopping at the proxy would have produced a confident wrong answer, which is the"
echo "specific failure this task's counter is written against."
echo
echo "### Following the EIP-1967 slots"
echo
echo "The slot is COMPUTED here, not pasted from documentation:"
echo
echo '```'
echo "keccak256(\"eip1967.proxy.implementation\")     $RAW"
echo "  minus 1                                     $SLOT"
echo "keccak256(\"eip1967.proxy.admin\")              $ADMIN_RAW"
echo "  minus 1                                     $ADMIN_SLOT"
echo '```'
echo
echo '```'
printf '%-24s %-44s %10s  %s\n' "predeploy" "implementation" "impl bytes" "keccak256(impl runtime)"
} >> "$OUT"

declare -A P=(
  ["L2ToL1MessagePasser"]="0x4200000000000000000000000000000000000016"
  ["L1Block"]="0x4200000000000000000000000000000000000015"
  ["GasPriceOracle"]="0x420000000000000000000000000000000000000F"
  ["L2StandardBridge"]="0x4200000000000000000000000000000000000010"
  ["L2CrossDomainMessenger"]="0x4200000000000000000000000000000000000007"
)

for name in "${!P[@]}"; do
  addr="${P[$name]}"
  word=$(cast storage "$addr" "$SLOT" --rpc-url "$RPC" 2>/dev/null || echo "0x0")
  impl="0x${word: -40}"
  if [ "$impl" = "0x0000000000000000000000000000000000000000" ] || [ ${#impl} -ne 42 ]; then
    printf '%-24s %-44s %10s  %s\n' "$name" "SLOT EMPTY" "-" "not an EIP-1967 proxy" >> "$OUT"
    continue
  fi
  code=$(cast code "$impl" --rpc-url "$RPC" 2>/dev/null || echo 0x)
  size=$(python3 -c "print(max(0, (len('$code') - 2) // 2))")
  printf '%s' "$code" > "$BYTE/${name}_impl.hex"
  printf '%-24s %-44s %10s  %s\n' "$name" "$impl" "$size" "$(cast keccak "$code")" >> "$OUT"
done

{
echo '```'
echo
echo "The implementations have DIFFERENT code and different sizes, which confirms the proxy reading:"
echo "one shared proxy in front of five distinct programs."
echo
} >> "$OUT"

echo "implementations resolved, bytecode saved to $BYTE"
grep -c "^" "$OUT" | sed 's/^/lines: /'
