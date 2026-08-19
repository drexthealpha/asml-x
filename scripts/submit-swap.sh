#!/usr/bin/env bash
# Signing shim for a REAL swap through the OKX Onchain OS router, on X Layer mainnet.
#
# The sibling of submit-take.sh. That one submits an approved decision to the order book this
# project deployed; this one submits an approved decision to the pools everyone else on X Layer
# trades in. Same contract with the runtime: arguments in, `TX=<hash>` out, cast does the signing
# (ADR-008), and nothing here decides anything.
#
# Args: <from_symbol> <to_symbol> <amount_whole> <decision_id>
# Prints: TX=<hash> on success.
#
# WHAT MAKES THIS SAFE, and none of it is trust in OKX:
#   - the amount is sized from the token's DECLARED decimals, never a typed exponent
#   - the calldata is fetched fresh per trade, never replayed from a file
#   - `minReceiveAmount` from the aggregator is passed to the contract, which REVERTS on a
#     measured shortfall (contracts/src/RouterExecutor.sol, proved by scripts/214)
#   - the router address is pinned immutably in the contract, so the calldata's `to` cannot
#     redirect anything
#
# EVIDENCE PATH: evidence/phase19/real-swaps.jsonl
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

FROM_SYM="${1:?from symbol required}"
TO_SYM="${2:?to symbol required}"
AMOUNT="${3:?amount required}"
DECISION_ID="${4:?decision id required}"

RPC="${ASML_RPC:-https://rpc.xlayer.tech}"
M="$REPO/deployments-mainnet.json"
EXECUTOR=$(python3 -c "import json;print(json.load(open('$M'))['routerExecutor'])")

# Fetch calldata for THIS trade. The recipient is the executor contract, because the router encodes
# the recipient into the calldata: passing a person's wallet here would send the proceeds there and
# the contract's balance check would correctly revert.
Q=$(python3 swap_calldata.py "$FROM_SYM" "$TO_SYM" "$AMOUNT" "$EXECUTOR") || {
  echo "quote failed: $Q" >&2
  exit 1
}

TOKEN_IN=$(echo "$Q" | python3 -c "import json,sys;print(json.load(sys.stdin)['from_address'])")
TOKEN_OUT=$(echo "$Q" | python3 -c "import json,sys;print(json.load(sys.stdin)['to_address'])")
AMOUNT_RAW=$(echo "$Q" | python3 -c "import json,sys;print(json.load(sys.stdin)['amount_raw'])")
MIN_OUT=$(echo "$Q" | python3 -c "import json,sys;print(json.load(sys.stdin)['min_receive'])")
CALLDATA=$(echo "$Q" | python3 -c "import json,sys;print(json.load(sys.stdin)['data'])")
VENUES=$(echo "$Q" | python3 -c "import json,sys;print(', '.join(json.load(sys.stdin)['venues']))")

PASS="$(keystore_pass)"
OUT=$(cast send "$EXECUTOR" \
  "route(address,address,uint256,uint256,bytes)(uint256)" \
  "$TOKEN_IN" "$TOKEN_OUT" "$AMOUNT_RAW" "$MIN_OUT" "$CALLDATA" \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>&1) || {
  echo "cast send failed: $OUT" >&2
  exit 1
}

TX=$(echo "$OUT" | python3 -c "import json,sys;print(json.load(sys.stdin)['transactionHash'])" 2>/dev/null)
STATUS=$(echo "$OUT" | python3 -c "import json,sys;print(json.load(sys.stdin)['status'])" 2>/dev/null)

if [ "$STATUS" != "0x1" ]; then
  echo "swap reverted, status $STATUS, tx $TX" >&2
  exit 1
fi

# Append the record. Written only AFTER a confirmed 0x1, so this file never contains a trade that
# did not happen.
mkdir -p "$REPO/evidence/phase19"
python3 - "$DECISION_ID" "$FROM_SYM" "$TO_SYM" "$AMOUNT_RAW" "$MIN_OUT" "$TX" "$VENUES" <<'PY'
import json, os, sys, time
repo = os.path.abspath(os.path.join(os.path.dirname(sys.argv[0]) or ".", ".."))
rec = {
    "decision_id": int(sys.argv[1]),
    "from": sys.argv[2], "to": sys.argv[3],
    "amount_raw": sys.argv[4], "min_receive": sys.argv[5],
    "tx": sys.argv[6], "venues": sys.argv[7],
    "chain_id": 196,
    "explorer": f"https://www.oklink.com/x-layer/evm/tx/{sys.argv[6]}",
    "at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
with open(os.path.join(repo, "evidence", "phase19", "real-swaps.jsonl"), "a",
          encoding="utf-8", newline="\n") as fh:
    fh.write(json.dumps(rec) + "\n")
PY

echo "TX=$TX"
