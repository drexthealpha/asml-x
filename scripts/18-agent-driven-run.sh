#!/usr/bin/env bash
# Task 4.2.6 and the Phase 4 live proof: the AGENT drives real onchain execution.
#
# Everything before this was script-driven. Here the Rust runtime reads the chain,
# computes signals, scores a candidate set, passes the winner through the risk gate,
# and submits it. The transaction hash traces back to a journal entry that contains
# the reasoning and the rejected alternatives.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$PATH"

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
BASE=$(python3 -c "import json;print(json.load(open('$J'))['tBASE'])")
QUOTE=$(python3 -c "import json;print(json.load(open('$J'))['tQUOTE'])")
EXEC=$(python3 -c "import json;print(json.load(open('$J'))['batchExecutor'])")
GUARD=$(python3 -c "import json;print(json.load(open('$J'))['riskGuard'])")
MARKET=$(python3 -c "import json;print(json.load(open('$J'))['marketId'])")

send() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo FAIL
}

echo "=== fund the executor on BOTH tokens ==="
echo -n "  mint tBASE to executor:  "; send "$BASE"  "mint(address,uint256)" "$EXEC" 500000000000000000000
echo -n "  mint tQUOTE to executor: "; send "$QUOTE" "mint(address,uint256)" "$EXEC" 500000000000000000000
echo "  exec tBASE:  $(cast call "$BASE" "balanceOf(address)(uint256)" "$EXEC" --rpc-url "$RPC" | awk '{print $1}')"
echo "  exec tQUOTE: $(cast call "$QUOTE" "balanceOf(address)(uint256)" "$EXEC" --rpc-url "$RPC" | awk '{print $1}')"

echo
echo "=== guard state before ==="
EXP_BEFORE=$(cast call "$GUARD" "exposureOf(bytes32)(uint256)" "$MARKET" --rpc-url "$RPC" | awk '{print $1}')
echo "  exposure: $EXP_BEFORE"
echo "  killed:   $(cast call "$GUARD" "killed()(bool)" --rpc-url "$RPC")"

cd "$REPO"
cargo build --release -p runtime 2>&1 | tail -2

echo
echo "=== asml run 3 : the agent decides AND submits ==="
ASML_REPO="$REPO" ./target/release/asml run 3

echo
echo "=== guard state after ==="
EXP_AFTER=$(cast call "$GUARD" "exposureOf(bytes32)(uint256)" "$MARKET" --rpc-url "$RPC" | awk '{print $1}')
echo "  exposure: $EXP_BEFORE -> $EXP_AFTER"
echo "  gross:    $(cast call "$GUARD" "gross()(uint256)" --rpc-url "$RPC" | awk '{print $1}')"
echo "  sumParts: $(cast call "$GUARD" "sumOfParts()(uint256)" --rpc-url "$RPC" | awk '{print $1}')"

echo
echo "=== last journal entry, abbreviated ==="
python3 - <<'PY'
import json, os
p = os.environ.get('ASML_REPO', '.') + '/evidence/journal.jsonl'
lines = [l for l in open(p) if l.strip()]
e = json.loads(lines[-1])
print("decision_id      ", e['decision_id'])
print("block            ", e['block_number'])
print("thesis           ", e['thesis'][:150])
print("confidence_bps   ", e['thesis_confidence_bps'])
print("risk_verdict     ", e['risk_verdict'])
print("action           ", e['action'])
print("tx_hash          ", e['tx_hash'])
print("candidates       ", len(e['candidates']))
chosen = [c for c in e['candidates'] if c['chosen']]
print("chosen           ", chosen[0]['label'] if chosen else None)
print("chosen score     ", chosen[0]['score_micro'] if chosen else None)
print()
print("top 4 rejected, with why:")
rej = sorted([c for c in e['candidates'] if not c['chosen']],
             key=lambda c: -int(c['score_micro']))[:4]
for c in rej:
    print(f"  {c['label'][:46]:48} score={c['score_micro']:>10}  {c['rejection_reason']}")
PY
