#!/usr/bin/env bash
# Record the FeeCollector's deploy block in deployments.json.
#
# The log scanner needs a floor. Without one, a cold backfill either scans from block 0 (which the
# RPC rejects 100 blocks at a time, forever) or from an arbitrary lookback, and then "I found no
# events" is indistinguishable from "I did not look far enough". With the deploy block recorded, the
# scanner can state `backfill_complete: true` and mean it.
#
# Derived here by binary search on `cast code`, rather than by remembering the deploy transaction:
# the contract has no code before its deploy block and code at every block after, which is a property
# of the chain rather than of a log this script would have to have kept.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

RPC="$XLAYER_TESTNET_RPC"
J="$REPO/deployments.json"
FEE=$(python3 -c "import json;print(json.load(open('$J'))['feeCollector'])")

python3 - "$FEE" "$RPC" "$J" <<'PY'
import json, subprocess, sys
fee, rpc, jpath = sys.argv[1], sys.argv[2], sys.argv[3]

def has_code(block):
    r = subprocess.run(
        ["cast", "code", fee, "--block", str(block), "--rpc-url", rpc],
        capture_output=True, text=True, timeout=60,
    )
    return r.returncode == 0 and len(r.stdout.strip()) > 4

head = int(subprocess.run(["cast", "block-number", "--rpc-url", rpc],
                          capture_output=True, text=True, timeout=60).stdout.strip())
if not has_code(head):
    print("no code at head; is this the right collector?")
    sys.exit(1)

# Walk back in doubling strides to bracket the deploy, then bisect. Costs ~2*log2(range) calls.
lo, step = head, 1
while lo > 0 and has_code(lo):
    step *= 2
    lo = max(0, head - step)
hi = min(head, lo + step)
print(f"bracketed: no code at {lo}, code at {hi}")

while hi - lo > 1:
    mid = (lo + hi) // 2
    if has_code(mid):
        hi = mid
    else:
        lo = mid

print(f"FeeCollector deploy block: {hi}")
d = json.load(open(jpath))
d["feeDeployBlock"] = hi
json.dump(d, open(jpath, "w"), indent=2)
print("recorded in deployments.json")
PY
