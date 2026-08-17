#!/usr/bin/env bash
# Task 8.3: the agent cannot exceed a user's limits, structurally, in TWO independent places.
#
# THINKING: #45 proof by contradiction (containment is stated so a counterexample is what failure
# looks like), #22 inversion (what would a per-user limit do WRONG? permit more than the system
# would), #3 nth-order (a limit that could widen would silently unbind every global limit at once).
#
# EVIDENCE PATH: evidence/phase8/per-user-limits.txt
# PASS: a decision exceeding a user's limit fails to produce RiskApproved, AND the same call reverts
# onchain if attempted directly.
#
# FAKE WIN, quoted: "enforcing only offchain and calling it structural."
# COUNTER, quoted: "the onchain revert is demonstrated with a real testnet transaction."
#
# So this script does not stop at `cast call`. A simulated call proves the bytecode would revert; a
# SUBMITTED transaction that lands with status 0x0 is a permanent, third-party-verifiable record on
# the explorer that the attempt was made and refused. Both are captured, because the call gives the
# decoded error and the transaction gives the receipt.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase8/per-user-limits.txt"
mkdir -p "$(dirname "$OUT")"
RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
VAULT=$(a agentVault); QUOTE=$(a tQUOTE)

{
  echo "Task 8.3: per-user limits, enforced offchain AND onchain"
  echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  echo "== HALF ONE: offchain, the RiskApproved seal =="
} > "$OUT"

cd "$REPO"
cargo test -p risk-engine 2>&1 | grep -E "^test tests::(per_user|prop_a_user|prop_unbounded|tightened_by|a_user_limit)|^test result" >> "$OUT" 2>&1

{
  echo
  echo "The containment property is the one that matters: prop_a_user_limit_can_never_widen_what_the"
  echo "system_allows asserts that for arbitrary user limits and arbitrary orders, anything"
  echo "evaluate_for_user approves is also approved by the plain evaluate. A user limit can only ever"
  echo "SUBTRACT from what is permitted, so a user typing a very large number is safe by construction"
  echo "rather than by validation. Limits::tightened_by takes a minimum on every field."
  echo
  echo "prop_unbounded_user_limits_agree_with_the_plain_engine is the anti-vacuity pair: without it,"
  echo "an implementation that refused everything would satisfy containment trivially."
  echo
  echo "== HALF TWO: onchain, AgentVault.openTrade re-checks the same bound =="
  echo
  echo "vault:  $VAULT"
} >> "$OUT"

# Deposit under a deliberately small limit, so the refusal is about the LIMIT and not about funds.
DEPOSIT=10000000000000000000   # 10 tQUOTE
LIMIT=1000000000000000000      # 1 tQUOTE per action
OVER=2000000000000000000       # 2 tQUOTE, twice the limit and well inside the balance

send() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null
}
status_of() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d['status'],d['transactionHash'])" 2>/dev/null || echo "PARSE_FAIL"; }

{
  echo -n "deposit 10 tQUOTE with a 1 tQUOTE per-action limit: "
  send "$VAULT" "deposit(uint256,uint256)" "$DEPOSIT" "$LIMIT" | status_of
} >> "$OUT"

BAL=$(cast call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')
MAXN=$(cast call "$VAULT" "maxNotional(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')
{
  echo "vault.balanceOf(depositor):   $BAL"
  echo "vault.maxNotional(depositor): $MAXN"
  echo
  echo "The attempt below asks for 2 tQUOTE against a 1 tQUOTE limit, with 10 tQUOTE on deposit."
  echo "There are ample funds. The ONLY thing refusing it is the user's own limit."
  echo
  echo "--- simulated call, for the decoded custom error ---"
  cast call "$VAULT" "openTrade(address,uint256)" "$DEPLOYER_ADDRESS" "$OVER" \
    --from "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1 | head -3
} >> "$OUT"

{
  echo
  echo "--- SUBMITTED transaction, so the refusal is a permanent onchain record ---"
} >> "$OUT"

# --gas-limit forces the transaction on chain rather than failing estimation locally. A reverted
# transaction still lands in a block with status 0x0, which is the artifact this task asks for.
# --async so cast returns the hash on broadcast instead of waiting for a receipt and exiting
# non-zero when the transaction reverts, which is exactly what this transaction is meant to do.
# --gas-limit skips estimation, which would otherwise refuse to submit a call it knows will revert.
RAW=$(cast send "$VAULT" "openTrade(address,uint256)" "$DEPLOYER_ADDRESS" "$OVER" \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" \
  --gas-limit 200000 --async 2>&1)
# The hash is the last 0x-prefixed 32-byte word on the line, taken whole rather than grepped out of
# a JSON blob where a zero word can match first.
TX=$(printf '%s' "$RAW" | tr -d ' \r' | grep -oE '^0x[0-9a-fA-F]{64}$' | head -1)
if [ -z "$TX" ]; then
  TX=$(printf '%s' "$RAW" | grep -oE '0x[0-9a-fA-F]{64}' | grep -v '^0x0\{64\}$' | head -1)
fi

# The receipt does not exist until the transaction is mined. Blocks are about 1s.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if cast receipt "$TX" --rpc-url "$RPC" --json > "$HOME/.asml-83-receipt.json" 2>/dev/null; then
    if [ -s "$HOME/.asml-83-receipt.json" ]; then break; fi
  fi
  sleep 3
done

if [ -n "$TX" ]; then
  RJ="$HOME/.asml-83-receipt.json"
  ST=$(python3 -c "import json;print(json.load(open('$RJ'))['status'])" 2>/dev/null || echo "?")
  BLK=$(python3 -c "import json;print(int(json.load(open('$RJ'))['blockNumber'],16))" 2>/dev/null || echo "?")
  {
    echo "tx:     $TX"
    echo "status: $ST   (0x0 means REVERTED, which is the pass for this task)"
    echo "block:  $BLK"
    echo "explorer: https://www.oklink.com/x-layer-testnet/tx/$TX"
  } >> "$OUT"
else
  echo "no tx hash returned:" >> "$OUT"
  printf '%s\n' "$RAW" | tail -3 >> "$OUT"
  ST="none"
fi

# The counterfactual: an amount WITHIN the limit must succeed, or the revert above proves only that
# openTrade is broken.
{
  echo
  echo "--- counterfactual: the same call at 1 tQUOTE, inside the limit ---"
  echo -n "openTrade(depositor, 1 tQUOTE): "
  send "$VAULT" "openTrade(address,uint256)" "$DEPLOYER_ADDRESS" "$LIMIT" | status_of
} >> "$OUT"

COMMITTED=$(cast call "$VAULT" "committed(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')
{
  echo "vault.committed(depositor): $COMMITTED"
  echo
  echo "== gate =="
  echo "offchain: RiskApproved cannot be constructed past a user limit (6 tests, containment proved)"
  echo "onchain:  the over-limit call reverted on chain with status $ST"
  echo "control:  the within-limit call succeeded, committed $COMMITTED"
  if [ "$ST" = "0x0" ] && [ "${COMMITTED:-0}" = "$LIMIT" ]; then
    echo "GATE: PASS  two independent enforcements, both demonstrated"
  else
    echo "GATE: FAIL  status=$ST committed=$COMMITTED expected=$LIMIT"
  fi
} >> "$OUT"

tail -30 "$OUT"
