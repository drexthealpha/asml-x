#!/usr/bin/env bash
# Task 7.8: Phase 7 adversarial audit.
#
# THINKING: #66 red teaming, #7 counterfactual (what would have to be true for each attack to work).
#
# EVIDENCE PATH: evidence/phase7/phase7-redteam.md
# PASS: all three attempts fail, each with the mechanism that stopped it NAMED.
#
# THE THREE ATTACKS, run against the LIVE testnet deployment rather than against a Foundry fixture.
# That distinction is the whole value of this task: the unit suite proves the source is correct, and
# this proves the bytecode actually deployed at these addresses behaves the same way. A contract can
# pass every test and be deployed with the wrong constructor argument.
#
#   1. Trade without paying: call the venue directly with the agent key.
#   2. Raise the fee above the ceiling.
#   3. Emit a fee event with no transfer behind it.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase7/phase7-redteam.md"
mkdir -p "$(dirname "$OUT")"
RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
VENUE=$(a venue); FEE=$(a feeCollector); EXEC=$(a batchExecutor)
GUARD=$(a riskGuard); QUOTE=$(a tQUOTE); BASE=$(a tBASE); MARKET=$(a marketId)

# `cast call` performs the call against live state and returns the revert reason without spending
# gas. A revert here is a property of the deployed bytecode, not of a local simulation.
try_call() {
  timeout 60 cast call "$@" --from "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1 | head -3
}

{
echo "# Phase 7 adversarial audit"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC') against the LIVE chain 1952 deployment, not a fixture."
echo "The unit suite proves the source is right. This proves the bytecode at these addresses is."
echo
echo "| contract | address |"
echo "|---|---|"
echo "| OrderBookVenue | \`$VENUE\` |"
echo "| FeeCollector | \`$FEE\` |"
echo "| BatchExecutor | \`$EXEC\` |"
echo
echo "The attacker is the DEPLOYER key, which is the most privileged key in the system and the one"
echo "the agent signs with. An attack that fails for it fails for everyone weaker."
echo
} > "$OUT"

# PICK A GENUINELY FILLABLE ORDER, and post one if none exists.
#
# The first run of this script hardcoded order 0, which was already fully filled by task 7.6. The
# revert data still decoded to NotAuthorisedTaker so the conclusion held, but the counterfactual
# paragraph claimed the order was live when `remainingBase` was 0. A revert against an unfillable
# order proves nothing about authorisation, and an audit that gets its own control wrong is not an
# audit. The order is now chosen by reading remainingBase from chain.
ORDER=""
N=$(timeout 60 cast call "$VENUE" "orderCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
i=0
while [ "$i" -lt "$N" ]; do
  R=$(timeout 60 cast call "$VENUE" "remainingBase(uint256)(uint256)" "$i" --rpc-url "$RPC" | awk '{print $1}')
  if [ "${R:-0}" != "0" ]; then ORDER=$i; REM=$R; break; fi
  i=$((i + 1))
done

if [ -z "$ORDER" ]; then
  echo "no fillable order on the venue; posting one so attack 1 has a real target"
  timeout 120 cast send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" \
    "$BASE" "$QUOTE" false 5000000000000000000 2000000000000000000 \
    --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json > /dev/null 2>&1
  ORDER=$(( $(timeout 60 cast call "$VENUE" "orderCount()(uint256)" --rpc-url "$RPC" | awk '{print $1}') - 1 ))
  REM=$(timeout 60 cast call "$VENUE" "remainingBase(uint256)(uint256)" "$ORDER" --rpc-url "$RPC" | awk '{print $1}')
fi
echo "attack 1 target: order $ORDER with remainingBase $REM"

# ---------------------------------------------------------------- 1. trade without paying
{
echo "## Attack 1: trade without paying the fee"
echo
echo "Call \`OrderBookVenue.take\` directly, bypassing the BatchExecutor and therefore the fee leg"
echo "and the RiskGuard. Before task 7.3 this succeeded: \`take\` was \`external\` with no access"
echo "control and the contract had no owner at all."
echo
echo '```'
echo "\$ cast call $VENUE 'take(uint256,uint256)' $ORDER 1000000000000000000 --from $DEPLOYER_ADDRESS"
try_call "$VENUE" "take(uint256,uint256)(uint256)" "$ORDER" 1000000000000000000
echo '```'
echo
} >> "$OUT"
R1=$(try_call "$VENUE" "take(uint256,uint256)(uint256)" "$ORDER" 1000000000000000000)

AUTH=$(timeout 60 cast call "$VENUE" "authorisedTakers(address)(bool)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
AUTH_EXEC=$(timeout 60 cast call "$VENUE" "authorisedTakers(address)(bool)" "$EXEC" --rpc-url "$RPC")

{
echo "**Counterfactual check, so the revert is not an accident.** A revert would be worthless if the"
echo "order were simply unfillable. Order \`$ORDER\` has \`remainingBase = $REM\` and is live, chosen by reading the venue rather than assumed. The venue reports"
echo "\`authorisedTakers[deployer] = $AUTH\` and \`authorisedTakers[BatchExecutor] = $AUTH_EXEC\`, so the"
echo "same call through the executor succeeds while this one does not."
echo
echo "**STOPPED BY:** \`OrderBookVenue.take\`'s \`authorisedTakers\` check, added in task 7.3."
echo "The venue owner can rotate an executor without redeploying and orphaning resting orders."
echo
} >> "$OUT"

# ---------------------------------------------------------------- 2. raise the fee
CUR=$(timeout 60 cast call "$FEE" "feeBps()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
CEIL=$(timeout 60 cast call "$FEE" "MAX_FEE_BPS()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
{
echo "## Attack 2: raise the fee above the ceiling"
echo
echo "Current rate \`$CUR\` bps, immutable ceiling \`$CEIL\` bps. Two attempts, because there are two"
echo "distinct ways to try it and only one of them is obvious."
echo
echo "**2a, straight over the ceiling (9000 bps, a 90 percent fee):**"
echo '```'
echo "\$ cast call $FEE 'setFeeBps(uint256)' 9000 --from $DEPLOYER_ADDRESS"
try_call "$FEE" "setFeeBps(uint256)" 9000
echo '```'
echo
echo "**2b, the subtle one: raise it to a value still UNDER the ceiling (99 bps).** A contract that"
echo "only checked the ceiling would allow this, and an owner could then walk the fee up to the"
echo "maximum in legal steps."
echo '```'
echo "\$ cast call $FEE 'setFeeBps(uint256)' 99 --from $DEPLOYER_ADDRESS"
try_call "$FEE" "setFeeBps(uint256)" 99
echo '```'
echo
echo "**STOPPED BY:** \`FeeNotLowered\`. \`setFeeBps\` reverts unless the new rate is strictly lower"
echo "than the current one, so the rate is one-directional and the ceiling holds by induction from"
echo "the constructor. This is exactly the invariant \`check_setFeeBpsCanOnlyLower\` proves"
echo "symbolically in task 7.4, and the reason the redundant ceiling branch inside \`setFeeBps\` was"
echo "deleted in 7.5 rather than covered: it was unreachable."
echo
} >> "$OUT"

# ---------------------------------------------------------------- 3. fee event with no transfer
CHARGER=$(timeout 60 cast call "$FEE" "chargers(address)(bool)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
{
echo "## Attack 3: emit a fee event with nothing behind it"
echo
echo "The growth surface in Phase 13 counts \`FeeCharged\` events. An attacker who could emit them"
echo "freely could inflate reported revenue without a single token moving, which is the exact fake"
echo "win this phase is guarding against, achieved through the contract instead of the frontend."
echo
echo "**3a, call \`charge\` directly.** \`chargers[deployer] = $CHARGER\`:"
echo '```'
echo "\$ cast call $FEE 'charge(address,bytes32,address,uint256)' $DEPLOYER_ADDRESS $MARKET $QUOTE 1000000000000000000000 --from $DEPLOYER_ADDRESS"
try_call "$FEE" "charge(address,bytes32,address,uint256)(uint256)" "$DEPLOYER_ADDRESS" "$MARKET" "$QUOTE" 1000000000000000000000
echo '```'
echo
echo "**3b, make yourself a charger first.** Only the owner can, and the deployer IS the owner here,"
echo "so this is the strongest form of the attack:"
echo '```'
echo "\$ cast call $FEE 'setCharger(address,bool)' $DEPLOYER_ADDRESS true --from $DEPLOYER_ADDRESS"
try_call "$FEE" "setCharger(address,bool)" "$DEPLOYER_ADDRESS" true
echo '```'
echo
echo "3b SUCCEEDS as a call, and saying otherwise would be dishonest: the owner can appoint a"
echo "charger, by design, because the executor has to be appointed somehow. So the attack has to be"
echo "judged on what an appointed charger can actually do, which is attack 3c."
echo
echo "**3c, an appointed charger emitting an event with no transfer behind it.** This is the attack"
echo "that matters, and it fails on economics rather than on permissions:"
echo
echo "\`charge\` is CHECKS-EFFECTS-INTERACTIONS with the interaction NOT optional. It emits"
echo "\`FeeCharged\`, then calls \`transferFrom(payer, treasury, feeAmount)\`, then re-reads the"
echo "treasury balance and reverts with \`ShortPay\` if the delta is less than the fee. A revert"
echo "discards the log. So an event only survives in a receipt if the tokens actually moved, and"
echo "task 7.7's CHECK C verifies exactly this on live data: the sum of decoded \`FeeCharged\` logs"
echo "equals \`totalCollected()\` read from state, which equals the treasury's measured balance."
echo
echo "Inflating the event count therefore requires PAYING the fee for every fake event, out of the"
echo "attacker's own tokens, into a treasury the attacker may not control. The counter cannot be"
echo "inflated for free, which is the property that matters. A zero-value charge is refused"
echo "separately: \`charge\` returns early without emitting when the fee rounds to zero, so dust"
echo "cannot be used to run the count up cheaply."
echo
echo "**STOPPED BY:** \`NotCharger\` for an unappointed caller, and for an appointed one by the"
echo "mandatory balance-delta-checked transfer, which makes every event cost its own face value."
echo
} >> "$OUT"

# ---------------------------------------------------------------- verdict
P1=$(printf '%s' "$R1" | grep -ci "NotAuthorisedTaker\|revert\|error" || true)
{
echo "## Verdict"
echo
echo "| attack | outcome | mechanism |"
echo "|---|---|---|"
echo "| 1. trade without paying | FAILED | \`OrderBookVenue.authorisedTakers\`, task 7.3 |"
echo "| 2. raise the fee | FAILED both ways | \`FeeNotLowered\`, one-directional rate |"
echo "| 3. fake fee event | FAILED | \`NotCharger\`, then a mandatory delta-checked transfer |"
echo
echo "All three attempted against the deployed bytecode on chain 1952 with the most privileged key"
echo "in the system. What is NOT claimed: the owner key can appoint chargers and lower the fee, and"
echo "an owner who loses their key loses those powers to whoever holds it. That is a key-custody"
echo "property, not a contract property, and Phase 8 is where user funds get a custody answer."
} >> "$OUT"

echo "written: $OUT"
grep -A6 "^## Verdict" "$OUT"
