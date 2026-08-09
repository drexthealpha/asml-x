#!/usr/bin/env bash
# Task 1.3.8 under the hybrid decision: is there ANY live venue with real
# activity on chain 1952? Samples recent blocks and ranks the most-called
# contracts. Decides whether "integrate a real third-party DEX" is viable at all.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
RPC="$XLAYER_TESTNET_RPC"
OUT="$REPO/evidence/exchangeos-recon"
mkdir -p "$OUT"

LATEST=$(cast block-number --rpc-url "$RPC")
echo "latest block: $LATEST"
echo "sampling 300 recent blocks for transaction targets..."

python3 - "$RPC" "$LATEST" <<'PY' | tee "$OUT/activity-scan.txt"
import json, sys, urllib.request
from collections import Counter

rpc, latest = sys.argv[1], int(sys.argv[2])

def batch(calls):
    req = urllib.request.Request(rpc, method='POST',
        headers={'content-type': 'application/json'},
        data=json.dumps(calls).encode())
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)

to_counter = Counter()
from_counter = Counter()
txs_total = 0
blocks_with_tx = 0
N = 300
STEP = 30

for start in range(latest - N, latest, STEP):
    calls = [{"jsonrpc":"2.0","id":i,"method":"eth_getBlockByNumber",
              "params":[hex(start+i), True]} for i in range(STEP)]
    try:
        res = batch(calls)
    except Exception as e:
        print("batch failed:", e); break
    for item in res:
        b = item.get('result')
        if not b: continue
        txs = b.get('transactions') or []
        if txs: blocks_with_tx += 1
        txs_total += len(txs)
        for t in txs:
            if t.get('to'): to_counter[t['to'].lower()] += 1
            if t.get('from'): from_counter[t['from'].lower()] += 1

print(f"blocks sampled:      {N}")
print(f"blocks with any tx:  {blocks_with_tx}")
print(f"total transactions:  {txs_total}")
print(f"tx per block avg:    {txs_total/N:.2f}")
print()
print("top 20 transaction TARGETS (candidate live venues):")
for addr, n in to_counter.most_common(20):
    print(f"  {n:6}  {addr}")
print()
print("distinct target contracts:", len(to_counter))
print("distinct senders:", len(from_counter))
PY
