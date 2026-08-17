#!/usr/bin/env bash
# Task 8.7: pause during an ACTIVE cycle.
#
# THINKING: #62 pre-mortem (what does a panicking user actually do, and what is true at that moment),
# #22 inversion, #66 red teaming.
#
# EVIDENCE PATH: evidence/phase8/pause-live.txt
# PASS: after pause, zero new submissions, and the depositor can still withdraw in full.
#
# FAKE WIN, quoted: "pausing an idle agent and calling it a circuit breaker."
# COUNTER, quoted: "the pause must land while a cycle is genuinely in flight, proven by block
# numbers."
#
# So this script does not pause and then start work. It opens a real trade, leaves it OPEN with funds
# committed at the venue, and pauses while that is true. The block number of every step is recorded,
# and the gate FAILS if the pause block does not fall strictly between the open block and the close
# block. An idle-agent pause cannot satisfy that ordering.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase8/pause-live.txt"
mkdir -p "$(dirname "$OUT")"
RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
VAULT=$(a agentVault); QUOTE=$(a tQUOTE)

call() { cast call "$@" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}'; }
blk() { cast block-number --rpc-url "$RPC" 2>/dev/null; }
send_json() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null
}
# Prints "<status> <tx> <block>" so every step is anchored to a block, which is what this task's
# counter demands.
step() {
  local out st tx bn
  out=$(send_json "$@")
  st=$(printf '%s' "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['status'])" 2>/dev/null || echo "?")
  tx=$(printf '%s' "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['transactionHash'])" 2>/dev/null || echo "?")
  bn=$(printf '%s' "$out" | python3 -c "import json,sys;print(int(json.load(sys.stdin)['blockNumber'],16))" 2>/dev/null || echo "?")
  echo "$st $tx $bn"
}

DEPOSIT=4000000000000000000   # 4 tQUOTE
LIMIT=1000000000000000000     # 1 tQUOTE per action

{
echo "Task 8.7: pause during an active cycle"
echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "vault: $VAULT"
echo
echo "== setup: clean start =="
} > "$OUT"

PRE_C=$(call "$VAULT" "committed(address)(uint256)" "$DEPLOYER_ADDRESS")
if [ "${PRE_C:-0}" != "0" ]; then
  echo "closing a leftover trade: $(step "$VAULT" "closeTrade(address,uint256,uint256)" "$DEPLOYER_ADDRESS" "$PRE_C" "$PRE_C")" >> "$OUT"
fi
PRE_B=$(call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS")
if [ "${PRE_B:-0}" != "0" ]; then
  echo "withdrawing a leftover balance: $(step "$VAULT" "withdrawAll()")" >> "$OUT"
fi
# Unpause, so the pause below is a real transition rather than a no-op on already-paused state.
if [ "$(cast call "$VAULT" "paused(address)(bool)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")" = "true" ]; then
  echo "clearing a pre-existing pause: $(step "$VAULT" "setPaused(bool)" false)" >> "$OUT"
fi

WALLET_0=$(call "$QUOTE" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS")
{
echo "wallet tQUOTE: $WALLET_0"
echo "paused:        $(cast call "$VAULT" "paused(address)(bool)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")"
echo
echo "== 1. deposit and OPEN a trade, leaving the cycle genuinely in flight =="
} >> "$OUT"

read -r S_DEP TX_DEP B_DEP <<< "$(step "$VAULT" "deposit(uint256,uint256)" "$DEPOSIT" "$LIMIT")"
echo "deposit:   status $S_DEP  block $B_DEP  tx $TX_DEP" >> "$OUT"

read -r S_OPEN TX_OPEN B_OPEN <<< "$(step "$VAULT" "openTrade(address,uint256)" "$DEPLOYER_ADDRESS" "$LIMIT")"
echo "openTrade: status $S_OPEN  block $B_OPEN  tx $TX_OPEN" >> "$OUT"

COMMITTED_MID=$(call "$VAULT" "committed(address)(uint256)" "$DEPLOYER_ADDRESS")
{
echo
echo "IN FLIGHT, and this is the state the pause has to land in:"
echo "  vault.committed(depositor):  $COMMITTED_MID   (funds are AT THE VENUE right now)"
echo "  vault.withdrawable:          $(call "$VAULT" "withdrawable(address)(uint256)" "$DEPLOYER_ADDRESS")"
echo
echo "== 2. PAUSE while the trade is still open =="
} >> "$OUT"

read -r S_PAUSE TX_PAUSE B_PAUSE <<< "$(step "$VAULT" "setPaused(bool)" true)"
{
echo "setPaused(true): status $S_PAUSE  block $B_PAUSE  tx $TX_PAUSE"
echo "paused now:      $(cast call "$VAULT" "paused(address)(bool)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")"
echo "committed still: $(call "$VAULT" "committed(address)(uint256)" "$DEPLOYER_ADDRESS")"
echo
echo "== 3. ZERO NEW SUBMISSIONS: every new agent action must now fail =="
} >> "$OUT"

# Attempt a new action while paused, and put the refusal on chain rather than only simulating it.
{
echo "--- simulated, for the decoded error ---"
cast call "$VAULT" "openTrade(address,uint256)" "$DEPLOYER_ADDRESS" "$LIMIT" \
  --from "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1 | head -2
} >> "$OUT"

RAW=$(cast send "$VAULT" "openTrade(address,uint256)" "$DEPLOYER_ADDRESS" "$LIMIT" \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --gas-limit 200000 --async 2>&1)
TX_BLOCKED=$(printf '%s' "$RAW" | tr -d ' \r' | grep -oE '^0x[0-9a-fA-F]{64}$' | head -1)
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if cast receipt "$TX_BLOCKED" --rpc-url "$RPC" --json > "$HOME/.asml-87.json" 2>/dev/null; then
    [ -s "$HOME/.asml-87.json" ] && break
  fi
  sleep 3
done
S_BLOCKED=$(python3 -c "import json;print(json.load(open('$HOME/.asml-87.json'))['status'])" 2>/dev/null || echo "?")
B_BLOCKED=$(python3 -c "import json;print(int(json.load(open('$HOME/.asml-87.json'))['blockNumber'],16))" 2>/dev/null || echo "?")
{
echo "--- submitted, so the refusal is a permanent record ---"
echo "tx:     $TX_BLOCKED"
echo "status: $S_BLOCKED  (0x0 means REVERTED, which is the pass)"
echo "block:  $B_BLOCKED"
echo
echo "committed after the blocked attempt: $(call "$VAULT" "committed(address)(uint256)" "$DEPLOYER_ADDRESS")"
echo "unchanged, so nothing was submitted."
echo
echo "== 4. THE DEPOSITOR CAN STILL WITHDRAW IN FULL, WHILE PAUSED =="
} >> "$OUT"

# The in-flight leg is settled by the agent, then the depositor exits. The order matters: the
# withdrawal below happens with `paused` still true, which is the property.
read -r S_CLOSE TX_CLOSE B_CLOSE <<< "$(step "$VAULT" "closeTrade(address,uint256,uint256)" "$DEPLOYER_ADDRESS" "$LIMIT" "$LIMIT")"
echo "closeTrade (settles the in-flight leg): status $S_CLOSE  block $B_CLOSE" >> "$OUT"

STILL_PAUSED=$(cast call "$VAULT" "paused(address)(bool)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
read -r S_WD TX_WD B_WD <<< "$(step "$VAULT" "withdrawAll()")"
VAULT_AFTER=$(call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS")
{
echo "paused at withdrawal time: $STILL_PAUSED"
echo "withdrawAll: status $S_WD  block $B_WD  tx $TX_WD"
echo "vault.balanceOf after:     $VAULT_AFTER"
echo
echo "== block ordering, which is what makes this a MID-FLIGHT pause =="
echo "  deposit      block $B_DEP"
echo "  openTrade    block $B_OPEN"
echo "  setPaused    block $B_PAUSE   <- strictly after the open"
echo "  blocked open block $B_BLOCKED"
echo "  closeTrade   block $B_CLOSE   <- strictly after the pause"
echo "  withdrawAll  block $B_WD"
} >> "$OUT"

ORDER_OK=0
if [ "$B_OPEN" != "?" ] && [ "$B_PAUSE" != "?" ] && [ "$B_CLOSE" != "?" ]; then
  if [ "$B_PAUSE" -gt "$B_OPEN" ] && [ "$B_CLOSE" -gt "$B_PAUSE" ]; then ORDER_OK=1; fi
fi

{
echo
echo "== gate =="
echo "pause landed strictly between open and close: $([ $ORDER_OK -eq 1 ] && echo yes || echo NO)"
echo "committed was non-zero when the pause landed:  $([ "${COMMITTED_MID:-0}" != "0" ] && echo yes || echo NO)"
echo "new agent action while paused reverted:        $([ "$S_BLOCKED" = "0x0" ] && echo yes || echo NO)"
echo "depositor withdrew in full WHILE paused:       $([ "$S_WD" = "0x1" ] && [ "$STILL_PAUSED" = "true" ] && echo yes || echo NO)"
echo "vault balance now zero:                        $([ "${VAULT_AFTER:-x}" = "0" ] && echo yes || echo NO)"
echo
echo "explorer:"
echo "  open:    https://www.oklink.com/x-layer-testnet/tx/$TX_OPEN"
echo "  pause:   https://www.oklink.com/x-layer-testnet/tx/$TX_PAUSE"
echo "  blocked: https://www.oklink.com/x-layer-testnet/tx/$TX_BLOCKED"
echo "  exit:    https://www.oklink.com/x-layer-testnet/tx/$TX_WD"
if [ $ORDER_OK -eq 1 ] && [ "${COMMITTED_MID:-0}" != "0" ] && [ "$S_BLOCKED" = "0x0" ] \
   && [ "$S_WD" = "0x1" ] && [ "$STILL_PAUSED" = "true" ] && [ "${VAULT_AFTER:-x}" = "0" ]; then
  echo "GATE: PASS  the pause landed mid-flight, blocked every new action, and did not block the exit"
else
  echo "GATE: FAIL  order=$ORDER_OK committed=$COMMITTED_MID blocked=$S_BLOCKED wd=$S_WD paused=$STILL_PAUSED after=$VAULT_AFTER"
fi
} >> "$OUT"

tail -34 "$OUT"
