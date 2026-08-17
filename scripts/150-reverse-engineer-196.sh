#!/usr/bin/env bash
# Task 11.7: REVERSE ENGINEER the real deployed contracts on chain 196, and 11.6's Exchange OS probe.
#
# THINKING: #60 map-territory (a whitepaper is a hypothesis; deployed bytecode is the territory),
# #49 skeptical (docs describe intent, chains record behaviour), #6 abductive (infer the interface
# from what the bytecode and its real transactions actually do).
#
# EVIDENCE PATH: docs/verified/onchain-reverse-engineering-196.md, evidence/phase11/bytecode/
# PASS: at least one contract fully characterised from bytecode and real transactions, with its
# selectors listed and one decoded transaction shown.
#
# FAKE WIN, quoted: "reading the docs, restating them, and calling it reverse engineering."
# COUNTER, quoted: "every DEMONSTRATED line must cite either a bytecode hash or a transaction hash.
# A line whose only source is a document is labelled INFERRED or it is deleted."
#
# SO NOTHING HERE READS A DOCUMENT. Every fact below comes from eth_getCode, eth_getLogs,
# eth_getTransactionByHash or eth_call against https://rpc.xlayer.tech. Selectors are extracted by
# scanning the runtime bytecode's own dispatch table, which is the contract telling you its own
# interface whether or not anybody published an ABI.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/docs/verified/onchain-reverse-engineering-196.md"
BYTE="$REPO/evidence/phase11/bytecode"
mkdir -p "$(dirname "$OUT")" "$BYTE"
RPC="https://rpc.xlayer.tech"

CHAIN_HEX=$(cast rpc eth_chainId --rpc-url "$RPC" 2>/dev/null | tr -d '"')
CHAIN=$(python3 -c "print(int('${CHAIN_HEX:-0x0}', 16))" 2>/dev/null || echo 0)
HEAD=$(cast block-number --rpc-url "$RPC")

{
echo "# Reverse engineering chain 196, from bytecode and transactions"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Chain id verified as $CHAIN at block $HEAD."
echo
echo "**Every DEMONSTRATED line below cites a bytecode hash or a transaction hash.** Nothing is taken"
echo "from documentation. Where a fact could only come from a document it is labelled INFERRED, and"
echo "the label is the point: a whitepaper is a hypothesis about a chain, and the chain is the only"
echo "thing that can settle it."
echo
echo "Surfaces used: \`$RPC\` for all chain reads. okx.com is unreachable from this machine (E9), so"
echo "oklink and xlayerscan are the explorer surfaces; none of them was needed for the facts below,"
echo "which come from the RPC directly."
echo
} > "$OUT"

[ "$CHAIN" = "196" ] || { echo "ABORT: not chain 196" >> "$OUT"; cat "$OUT"; exit 1; }

# ---------------------------------------------------------------- candidate addresses
# Standard predeploys an OP Stack chain has by construction, plus the bridge. These are addresses
# defined by the STACK, not by a vendor's documentation: if X Layer is OP Stack, they are there, and
# if they are not there then it is not OP Stack, which is itself a finding.
declare -A CANDIDATES=(
  ["L2ToL1MessagePasser"]="0x4200000000000000000000000000000000000016"
  ["L1Block"]="0x4200000000000000000000000000000000000015"
  ["GasPriceOracle"]="0x420000000000000000000000000000000000000F"
  ["L2StandardBridge"]="0x4200000000000000000000000000000000000010"
  ["L2CrossDomainMessenger"]="0x4200000000000000000000000000000000000007"
  ["WrappedOKB"]="0xe538905cf8410324e03A5A23C1c177a474D59b2b"
  ["Multicall3"]="0xcA11bde05977b3631167028862bE2a173976CA11"
)

{
echo "## Contracts found on chain 196"
echo
echo '```'
printf '%-24s %-44s %10s  %s\n' "name" "address" "code bytes" "keccak256(runtime)"
} >> "$OUT"

FOUND=()
for name in "${!CANDIDATES[@]}"; do
  addr="${CANDIDATES[$name]}"
  code=$(cast code "$addr" --rpc-url "$RPC" 2>/dev/null || echo 0x)
  size=$(python3 -c "print(max(0, (len('$code') - 2) // 2))")
  if [ "$size" -gt 0 ]; then
    printf '%s' "$code" > "$BYTE/$name.hex"
    h=$(cast keccak "$code")
    printf '%-24s %-44s %10s  %s\n' "$name" "$addr" "$size" "$h" >> "$OUT"
    FOUND+=("$name:$addr")
  else
    printf '%-24s %-44s %10s  %s\n' "$name" "$addr" "0" "NO CODE" >> "$OUT"
  fi
done

{
echo '```'
echo
echo "Runtime bytecode for every contract with code is saved under \`evidence/phase11/bytecode/\`."
echo "The keccak hash is what makes each line above checkable: anybody can re-fetch the code and"
echo "confirm the hash without trusting this file."
echo
} >> "$OUT"

# ---------------------------------------------------------------- selector extraction
{
echo "## Selectors, extracted from the dispatch table"
echo
echo "Solidity compiles a function dispatcher into a sequence of \`PUSH4 <selector>\` comparisons"
echo "against the first four bytes of calldata. Scanning the runtime bytecode for PUSH4 (opcode"
echo "0x63) recovers the selector set the contract will actually respond to, which is the contract"
echo "describing its own interface. No published ABI is consulted."
echo
} >> "$OUT"

python3 - "$BYTE" "$OUT" <<'PY'
import os
import sys

byte_dir, out_path = sys.argv[1], sys.argv[2]

# Known 4byte signatures for the selectors an OP Stack predeploy is expected to expose. Matching is
# LOCAL: the selector is computed from the signature and compared, so a match is a proof rather than
# a lookup anybody has to trust.
import hashlib

def keccak(data: bytes) -> bytes:
    # Minimal keccak-256, because hashlib does not ship it and a network 4byte lookup would make this
    # depend on a service rather than on arithmetic.
    RC = [0x0000000000000001,0x0000000000008082,0x800000000000808A,0x8000000080008000,
          0x000000000000808B,0x0000000080000001,0x8000000080008081,0x8000000000008009,
          0x000000000000008A,0x0000000000000088,0x0000000080008009,0x000000008000000A,
          0x000000008000808B,0x800000000000008B,0x8000000000008089,0x8000000000008003,
          0x8000000000008002,0x8000000000000080,0x000000000000800A,0x800000008000000A,
          0x8000000080008081,0x8000000000008080,0x0000000080000001,0x8000000080008008]
    R = [[0,36,3,41,18],[1,44,10,45,2],[62,6,43,15,61],[28,55,25,21,56],[27,20,39,8,14]]
    def rol(x, n): return ((x << n) | (x >> (64 - n))) & 0xFFFFFFFFFFFFFFFF
    rate = 136
    padded = bytearray(data)
    padded.append(0x01)
    while len(padded) % rate != 0:
        padded.append(0x00)
    padded[-1] |= 0x80
    S = [[0]*5 for _ in range(5)]
    for off in range(0, len(padded), rate):
        block = padded[off:off+rate]
        for i in range(rate // 8):
            x, y = i % 5, i // 5
            S[x][y] ^= int.from_bytes(block[i*8:(i+1)*8], "little")
        for rnd in range(24):
            C = [S[x][0] ^ S[x][1] ^ S[x][2] ^ S[x][3] ^ S[x][4] for x in range(5)]
            D = [C[(x-1) % 5] ^ rol(C[(x+1) % 5], 1) for x in range(5)]
            for x in range(5):
                for y in range(5):
                    S[x][y] ^= D[x]
            B = [[0]*5 for _ in range(5)]
            for x in range(5):
                for y in range(5):
                    B[y][(2*x + 3*y) % 5] = rol(S[x][y], R[x][y])
            for x in range(5):
                for y in range(5):
                    S[x][y] = B[x][y] ^ ((~B[(x+1) % 5][y]) & B[(x+2) % 5][y] & 0xFFFFFFFFFFFFFFFF)
            S[0][0] ^= RC[rnd]
    out = b""
    for i in range(4):
        x, y = i % 5, i // 5
        out += S[x][y].to_bytes(8, "little")
    return out[:32]

SIGS = [
    "initiateWithdrawal(address,uint256,bytes)", "burn()", "nonce()", "sentMessages(bytes32)",
    "number()", "timestamp()", "basefee()", "hash()", "sequenceNumber()", "batcherHash()",
    "l1FeeOverhead()", "l1FeeScalar()", "setL1BlockValues(uint64,uint64,uint256,bytes32,uint64,bytes32,uint256,uint256)",
    "getL1Fee(bytes)", "getL1GasUsed(bytes)", "gasPrice()", "baseFee()", "overhead()", "scalar()",
    "decimals()", "version()", "bridgeETH(uint32,bytes)", "bridgeERC20(address,address,uint256,uint32,bytes)",
    "withdraw(address,uint256,uint32,bytes)", "finalizeDeposit(address,address,address,address,uint256,bytes)",
    "sendMessage(address,bytes,uint32)", "relayMessage(uint256,address,address,uint256,uint256,bytes)",
    "messageNonce()", "xDomainMessageSender()", "OTHER_MESSENGER()",
    "aggregate3((address,bool,bytes)[])", "getBlockNumber()", "getEthBalance(address)",
    "deposit()", "withdraw(uint256)", "totalSupply()", "balanceOf(address)", "transfer(address,uint256)",
    "approve(address,uint256)", "allowance(address,address)", "transferFrom(address,address,uint256)",
    "name()", "symbol()",
]
KNOWN = {"0x" + keccak(s.encode()).hex()[:8]: s for s in SIGS}

lines = []
for fn in sorted(os.listdir(byte_dir)):
    if not fn.endswith(".hex"):
        continue
    name = fn[:-4]
    code = open(os.path.join(byte_dir, fn)).read().strip()
    if code.startswith("0x"):
        code = code[2:]
    raw = bytes.fromhex(code)

    # PUSH4 is 0x63. Collect every 4-byte immediate; the dispatcher's comparisons are among them.
    sels = []
    i = 0
    while i < len(raw):
        op = raw[i]
        if op == 0x63 and i + 5 <= len(raw):
            sels.append("0x" + raw[i+1:i+5].hex())
            i += 5
        elif 0x60 <= op <= 0x7F:
            i += 1 + (op - 0x5F)
        else:
            i += 1

    uniq = sorted(set(sels))
    matched = [(s, KNOWN[s]) for s in uniq if s in KNOWN]
    lines.append((name, len(raw), len(uniq), matched, uniq))

with open(out_path, "a", encoding="utf-8") as fh:
    for name, size, nsel, matched, uniq in lines:
        fh.write(f"### {name}\n\n")
        fh.write("```\n")
        fh.write(f"runtime bytes      {size}\n")
        fh.write(f"PUSH4 immediates   {nsel} unique\n")
        fh.write(f"matched signatures {len(matched)}\n")
        fh.write("```\n\n")
        if matched:
            fh.write("Selectors identified by computing keccak256 of the signature LOCALLY and\n")
            fh.write("comparing, so each match is arithmetic rather than a lookup to be trusted:\n\n")
            fh.write("```\n")
            for sel, sig in matched:
                fh.write(f"  {sel}  {sig}\n")
            fh.write("```\n\n")
        else:
            fh.write("No signature from the probe set matched. The unmatched immediates are still\n")
            fh.write("recorded in the bytecode file; a PUSH4 is not always a selector, so absence of a\n")
            fh.write("match is weak evidence either way.\n\n")
PY

echo "written: $OUT"
ls -la "$BYTE" | tail -8
