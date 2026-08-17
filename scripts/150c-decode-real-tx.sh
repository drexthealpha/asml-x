#!/usr/bin/env bash
# Task 11.7, the part that makes it reverse engineering rather than inventory: selectors from the
# IMPLEMENTATIONS, and one real transaction decoded end to end.
#
# The proxies have no dispatch table. The implementations do. So selector extraction runs on the
# implementation bytecode saved by 150b, and then a real transaction from a real block is decoded
# against what was found.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/docs/verified/onchain-reverse-engineering-196.md"
BYTE="$REPO/evidence/phase11/bytecode"
RPC="https://rpc.xlayer.tech"
HEAD=$(cast block-number --rpc-url "$RPC")

{
echo
echo "## Selectors, from the IMPLEMENTATIONS"
echo
echo "Extracted by scanning each implementation's runtime bytecode for PUSH4 immediates, then"
echo "identifying them by computing keccak256 of a candidate signature LOCALLY and comparing. Every"
echo "match below is arithmetic, not a lookup against a service that could be wrong or offline."
echo
} >> "$OUT"

python3 - "$BYTE" "$OUT" <<'PY'
import os, sys

byte_dir, out_path = sys.argv[1], sys.argv[2]

def keccak(data: bytes) -> bytes:
    RC=[0x0000000000000001,0x0000000000008082,0x800000000000808A,0x8000000080008000,
        0x000000000000808B,0x0000000080000001,0x8000000080008081,0x8000000000008009,
        0x000000000000008A,0x0000000000000088,0x0000000080008009,0x000000008000000A,
        0x000000008000808B,0x800000000000008B,0x8000000000008089,0x8000000000008003,
        0x8000000000008002,0x8000000000000080,0x000000000000800A,0x800000008000000A,
        0x8000000080008081,0x8000000000008080,0x0000000080000001,0x8000000080008008]
    R=[[0,36,3,41,18],[1,44,10,45,2],[62,6,43,15,61],[28,55,25,21,56],[27,20,39,8,14]]
    rol=lambda x,n: ((x<<n)|(x>>(64-n))) & 0xFFFFFFFFFFFFFFFF
    rate=136
    p=bytearray(data); p.append(0x01)
    while len(p)%rate: p.append(0)
    p[-1]|=0x80
    S=[[0]*5 for _ in range(5)]
    for off in range(0,len(p),rate):
        blk=p[off:off+rate]
        for i in range(rate//8):
            S[i%5][i//5]^=int.from_bytes(blk[i*8:(i+1)*8],"little")
        for rnd in range(24):
            C=[S[x][0]^S[x][1]^S[x][2]^S[x][3]^S[x][4] for x in range(5)]
            D=[C[(x-1)%5]^rol(C[(x+1)%5],1) for x in range(5)]
            for x in range(5):
                for y in range(5): S[x][y]^=D[x]
            B=[[0]*5 for _ in range(5)]
            for x in range(5):
                for y in range(5): B[y][(2*x+3*y)%5]=rol(S[x][y],R[x][y])
            for x in range(5):
                for y in range(5):
                    S[x][y]=B[x][y]^((~B[(x+1)%5][y]) & B[(x+2)%5][y] & 0xFFFFFFFFFFFFFFFF)
            S[0][0]^=RC[rnd]
    o=b""
    for i in range(4): o+=S[i%5][i//5].to_bytes(8,"little")
    return o[:32]

SIGS = [
 "number()","timestamp()","basefee()","hash()","sequenceNumber()","batcherHash()","l1FeeOverhead()",
 "l1FeeScalar()","setL1BlockValues(uint64,uint64,uint256,bytes32,uint64,bytes32,uint256,uint256)",
 "DEPOSITOR_ACCOUNT()","blobBaseFee()","blobBaseFeeScalar()","baseFeeScalar()","isEcotone()",
 "getL1Fee(bytes)","getL1GasUsed(bytes)","gasPrice()","baseFee()","overhead()","scalar()","decimals()",
 "version()","setEcotone()","setFjord()","isFjord()","getL1FeeUpperBound(uint256)",
 "initiateWithdrawal(address,uint256,bytes)","burn()","nonce()","sentMessages(bytes32)","messageNonce()",
 "bridgeETH(uint32,bytes)","bridgeETHTo(address,uint32,bytes)","bridgeERC20(address,address,uint256,uint32,bytes)",
 "bridgeERC20To(address,address,address,uint256,uint32,bytes)","withdraw(address,uint256,uint32,bytes)",
 "withdrawTo(address,address,uint256,uint32,bytes)","finalizeDeposit(address,address,address,address,uint256,bytes)",
 "finalizeBridgeETH(address,address,uint256,bytes)","finalizeBridgeERC20(address,address,address,address,uint256,bytes)",
 "MESSENGER()","OTHER_BRIDGE()","l1TokenBridge()","deposits(address,address)",
 "sendMessage(address,bytes,uint32)","relayMessage(uint256,address,address,uint256,uint256,bytes)",
 "xDomainMessageSender()","OTHER_MESSENGER()","successfulMessages(bytes32)","failedMessages(bytes32)",
 "baseGas(bytes,uint32)","MESSAGE_VERSION()","paused()",
 "totalSupply()","balanceOf(address)","transfer(address,uint256)","approve(address,uint256)",
 "allowance(address,address)","transferFrom(address,address,uint256)","name()","symbol()",
 "deposit()","withdraw(uint256)","aggregate3((address,bool,bytes)[])","getBlockNumber()",
]
KNOWN = {"0x"+keccak(s.encode()).hex()[:8]: s for s in SIGS}

def selectors(path):
    code = open(path).read().strip()
    if code.startswith("0x"): code = code[2:]
    raw = bytes.fromhex(code)
    out, i = [], 0
    while i < len(raw):
        op = raw[i]
        if op == 0x63 and i+5 <= len(raw):
            out.append("0x"+raw[i+1:i+5].hex()); i += 5
        elif 0x60 <= op <= 0x7F:
            i += 1 + (op - 0x5F)
        else:
            i += 1
    return sorted(set(out))

with open(out_path, "a", encoding="utf-8") as fh:
    for fn in sorted(os.listdir(byte_dir)):
        if not fn.endswith("_impl.hex"): continue
        name = fn[:-9]
        sels = selectors(os.path.join(byte_dir, fn))
        matched = [(s, KNOWN[s]) for s in sels if s in KNOWN]
        fh.write(f"### {name}\n\n```\n")
        fh.write(f"unique PUSH4 immediates  {len(sels)}\n")
        fh.write(f"identified signatures    {len(matched)}\n```\n\n")
        if matched:
            fh.write("```\n")
            for s, sig in matched:
                fh.write(f"  {s}  {sig}\n")
            fh.write("```\n\n")
        else:
            fh.write("None of the probe signatures matched. Recorded as-is: a PUSH4 is not always a\n")
            fh.write("selector, so no match is weak evidence rather than proof of absence.\n\n")
PY

# ---------------------------------------------------------------- one real transaction, decoded
{
echo "## One real transaction, decoded end to end"
echo
echo "Everything above characterises code. This reads what the chain actually DID with it."
echo
} >> "$OUT"

# Walk back from head until a block with transactions turns up.
BLK=$HEAD
TX=""
for _ in $(seq 1 40); do
  TX=$(cast block "$BLK" --rpc-url "$RPC" --json 2>/dev/null \
    | python3 -c "import json,sys
try:
    t=json.load(sys.stdin).get('transactions') or []
    print(t[0] if t else '')
except Exception:
    print('')" 2>/dev/null)
  [ -n "$TX" ] && break
  BLK=$((BLK - 1))
done

if [ -z "$TX" ]; then
  echo "No transaction found in the last 40 blocks. Recorded rather than fabricated." >> "$OUT"
else
  cast tx "$TX" --rpc-url "$RPC" --json > "$HOME/.asml-196-tx.json" 2>/dev/null
  cast receipt "$TX" --rpc-url "$RPC" --json > "$HOME/.asml-196-rcpt.json" 2>/dev/null

  python3 - "$HOME/.asml-196-tx.json" "$HOME/.asml-196-rcpt.json" "$OUT" "$TX" "$BLK" <<'PY'
import json, sys
tx = json.load(open(sys.argv[1]))
rc = json.load(open(sys.argv[2]))
out, txh, blk = sys.argv[3], sys.argv[4], sys.argv[5]

def h2i(v):
    if isinstance(v, str) and v.startswith("0x"): return int(v, 16)
    return v

data = tx.get("input") or tx.get("data") or "0x"
with open(out, "a", encoding="utf-8") as fh:
    fh.write("```\n")
    fh.write(f"transaction   {txh}\n")
    fh.write(f"block         {blk}\n")
    fh.write(f"from          {tx.get('from')}\n")
    fh.write(f"to            {tx.get('to')}\n")
    fh.write(f"value         {h2i(tx.get('value'))} wei\n")
    fh.write(f"gas limit     {h2i(tx.get('gas'))}\n")
    fh.write(f"gas used      {h2i(rc.get('gasUsed'))}\n")
    fh.write(f"status        {rc.get('status')}\n")
    fh.write(f"calldata      {len(data)//2 - 1} bytes\n")
    if len(data) >= 10:
        fh.write(f"selector      {data[:10]}\n")
        body = data[10:]
        words = [body[i:i+64] for i in range(0, len(body), 64)]
        fh.write(f"argument words {len(words)}\n")
        for i, w in enumerate(words[:6]):
            n = int(w, 16)
            addr = "0x" + w[-40:]
            fh.write(f"  arg[{i}]  0x{w}\n")
            fh.write(f"          as uint  {n}\n")
            if int(w[:24], 16) == 0:
                fh.write(f"          as address {addr}\n")
    logs = rc.get("logs") or []
    fh.write(f"logs          {len(logs)}\n")
    for i, lg in enumerate(logs[:3]):
        fh.write(f"  log[{i}] address {lg['address']}\n")
        for j, t in enumerate(lg.get("topics", [])[:3]):
            fh.write(f"        topic{j} {t}\n")
    fh.write("```\n\n")
    fh.write("Every field above is from `eth_getTransactionByHash` and `eth_getTransactionReceipt`.\n")
    fh.write("The selector is the first four bytes of the real calldata; the argument words are the\n")
    fh.write("ABI encoding as the chain stored it, shown raw and interpreted both ways so nothing is\n")
    fh.write("asserted about the type that the bytes do not support.\n\n")
PY
fi

echo "written: $OUT"
grep -c "^" "$OUT" | sed 's/^/lines: /'
