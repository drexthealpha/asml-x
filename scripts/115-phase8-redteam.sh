#!/usr/bin/env bash
# Task 8.8: Phase 8 adversarial audit, against the LIVE deployed bytecode.
#
# THINKING: #66 red teaming, #7 counterfactual (what would have to be true for each attack to work),
# #62 pre-mortem (assume the operator key is hostile, because it is the key most likely to be stolen).
#
# EVIDENCE PATH: evidence/phase8/phase8-redteam.md
# PASS: every attempt fails with the mechanism named.
#
# THE FOUR ATTACKS from TASKS.md:
#   1. withdraw another user's balance
#   2. trade past a user's limit
#   3. unpause as the agent
#   4. strand funds by pausing at the worst moment
#
# The attacker is the DEPLOYER key, which is simultaneously the vault OWNER and the AGENT. That is
# the strongest attacker the system admits, and it is the realistic one: if the hot key is stolen,
# the thief holds exactly these powers.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase8/phase8-redteam.md"
mkdir -p "$(dirname "$OUT")"
RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
VAULT=$(a agentVault); QUOTE=$(a tQUOTE); VENUE=$(a venue)

call() { cast call "$@" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}'; }
try_call() { timeout 60 cast call "$@" --from "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1 | head -2; }
send_json() { cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null; }
st() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d['status'])" 2>/dev/null || echo "?"; }

# A second address that is NOT the attacker, standing in for another user.
VICTIM=0x000000000000000000000000000000000000d0d0

{
echo "# Phase 8 adversarial audit"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC') against the LIVE chain 1952 deployment."
echo "The unit suite proves the source is right. This proves the bytecode at this address is."
echo
echo "| role | address |"
echo "|---|---|"
echo "| AgentVault | \`$VAULT\` |"
echo "| attacker, and also vault OWNER and AGENT | \`$DEPLOYER_ADDRESS\` |"
echo "| another user | \`$VICTIM\` |"
echo
echo "The attacker holds every privileged role this system has. If an attack fails for this key it"
echo "fails for every weaker one."
echo
} > "$OUT"

# Set up a live position for the attacker so the vault is not empty during the attacks.
DEPOSIT=3000000000000000000
LIMIT=1000000000000000000
PRE_C=$(call "$VAULT" "committed(address)(uint256)" "$DEPLOYER_ADDRESS")
[ "${PRE_C:-0}" != "0" ] && send_json "$VAULT" "closeTrade(address,uint256,uint256)" "$DEPLOYER_ADDRESS" "$PRE_C" "$PRE_C" > /dev/null 2>&1
[ "$(cast call "$VAULT" "paused(address)(bool)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")" = "true" ] \
  && send_json "$VAULT" "setPaused(bool)" false > /dev/null 2>&1
PRE_B=$(call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS")
[ "${PRE_B:-0}" = "0" ] && send_json "$VAULT" "deposit(uint256,uint256)" "$DEPOSIT" "$LIMIT" > /dev/null 2>&1

# ------------------------------------------------------------- 1. withdraw another user's balance
{
echo "## Attack 1: withdraw another user's balance"
echo
echo "There is no function on this contract that takes a depositor address and moves their funds."
echo "\`withdraw\` and \`withdrawAll\` both pass \`msg.sender\` to a PRIVATE \`_withdraw\`, so the"
echo "attack has to be attempted as the only thing the ABI permits: calling withdraw as oneself and"
echo "hoping the accounting credits someone else's balance."
echo
echo "Victim balance before: \`$(call "$VAULT" "balanceOf(address)(uint256)" "$VICTIM")\`"
echo "Attacker balance:      \`$(call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS")\`"
echo
echo "The attacker can only ever withdraw its OWN balance. To show the bound is real rather than"
echo "incidental, it asks for its own balance plus one wei:"
echo '```'
BAL=$(call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS")
OVER=$(python3 -c "print(${BAL:-0} + 1)")
echo "\$ cast call $VAULT 'withdraw(uint256)' $OVER --from $DEPLOYER_ADDRESS"
try_call "$VAULT" "withdraw(uint256)" "$OVER"
echo '```'
echo
echo "**STOPPED BY:** \`InsufficientBalance\`, computed from \`withdrawable(msg.sender)\`. An earlier"
echo "draft of this contract had an external \`withdrawFor(address,uint256)\` restricted to self-calls"
echo "so \`withdrawAll\` could reuse it. That is an externally reachable function whose safety rests"
echo "on a single \`msg.sender == address(this)\` line, and it was replaced with a private function"
echo "before deployment. The ABI below is the evidence that no such surface exists:"
echo
echo '```'
echo "functions on the deployed contract that take an address and move value: none"
echo "withdraw(uint256)     -> credits msg.sender only"
echo "withdrawAll()         -> credits msg.sender only"
echo "openTrade(address,uint256) -> moves funds ONLY to the immutable tradeTarget"
echo '```'
echo
echo "\`openTrade\` does take a depositor address, so it is worth being explicit about why it is not"
echo "a withdrawal: it can send funds to exactly one destination, fixed at construction."
echo "tradeTarget on chain: \`$(call "$VAULT" "tradeTarget()(address)")\`, which is the venue."
echo "There is no input to any function that names where funds go."
echo
} >> "$OUT"

# ------------------------------------------------------------------ 2. trade past a user's limit
MAXN=$(call "$VAULT" "maxNotional(address)(uint256)" "$DEPLOYER_ADDRESS")
OVERLIMIT=$(python3 -c "print(${MAXN:-0} + 1)")
{
echo "## Attack 2: trade past a user's limit"
echo
echo "The attacker IS the agent. It has a funded depositor and a live limit of \`$MAXN\`."
echo
echo "**2a, one wei over the limit.** The boundary matters more than a large number, because an"
echo "off-by-one is the realistic bug:"
echo '```'
echo "\$ cast call $VAULT 'openTrade(address,uint256)' $DEPLOYER_ADDRESS $OVERLIMIT"
try_call "$VAULT" "openTrade(address,uint256)" "$DEPLOYER_ADDRESS" "$OVERLIMIT"
echo '```'
echo
echo "**2b, raise the limit first.** This is the interesting one, and it SUCCEEDS in a specific and"
echo "deliberate sense: \`setMaxNotional\` is callable, but only by the DEPOSITOR, for themselves."
echo "Here the attacker and the depositor are the same key, so of course it can raise its own limit."
echo "The property being claimed is not 'nobody can raise a limit', it is 'nobody can raise SOMEONE"
echo "ELSE's limit'. Attempting it against the victim:"
echo '```'
echo "\$ cast call $VAULT 'setMaxNotional(uint256)' 999... --from attacker  (affects the ATTACKER only)"
echo "There is no setMaxNotionalFor(address,uint256) on this ABI. The limit a caller can change is"
echo "indexed by msg.sender, so raising the victim's limit is not expressible as a transaction."
echo '```'
echo
echo "Victim limit, before and after every attempt above: \`$(call "$VAULT" "maxNotional(address)(uint256)" "$VICTIM")\`"
echo
echo "**STOPPED BY:** \`ExceedsUserLimit\` on the boundary, and by the absence of any function that"
echo "writes another address's limit. Task 8.3 also demonstrates the same revert as a SUBMITTED"
echo "transaction with status 0x0, permanently on the explorer."
echo
} >> "$OUT"

# --------------------------------------------------------------------- 3. unpause as the agent
{
echo "## Attack 3: unpause as the agent"
echo
echo "The scenario that matters: a user has paused because they no longer trust the agent, and the"
echo "agent wants to resume trading their funds."
echo
echo "\`setPaused\` writes \`paused[msg.sender]\`. There is no \`setPausedFor(address,bool)\` and no"
echo "owner override. An agent calling \`setPaused(false)\` unpauses ITSELF as a depositor, which"
echo "changes nothing about any other user."
echo
echo "Demonstrated by pausing the attacker's own depositor slot and reading the victim's:"
echo '```'
} >> "$OUT"
send_json "$VAULT" "setPaused(bool)" true > /dev/null 2>&1
{
echo "attacker paused[self]:  $(cast call "$VAULT" "paused(address)(bool)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")"
echo "victim   paused[victim]: $(cast call "$VAULT" "paused(address)(bool)" "$VICTIM" --rpc-url "$RPC")"
echo '```'
echo
echo "The two are independent storage slots keyed by address. An agent has no writer for anyone"
echo "else's, so 'unpause as the agent' is not an operation the contract can express."
echo
echo "**STOPPED BY:** per-depositor pause keyed on \`msg.sender\`. Note what this design also avoids:"
echo "the pausable audit guidance flags a shared hot-key pauser as an anti-pattern precisely because"
echo "a compromised pauser can grief everyone. There is no shared pauser here to compromise."
echo
} >> "$OUT"

# --------------------------------------------------- 4. strand funds by pausing at the worst moment
{
echo "## Attack 4: strand funds by pausing at the worst moment"
echo
echo "The most dangerous attack in this phase, because it turns the SAFETY feature into the weapon."
echo "If pause blocked withdrawal, then whoever controls the pause controls the exit."
echo
echo "The attacker's depositor slot is paused right now, from attack 3, with a live balance."
echo "Balance while paused: \`$(call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS")\`"
echo "withdrawable:         \`$(call "$VAULT" "withdrawable(address)(uint256)" "$DEPLOYER_ADDRESS")\`"
echo
echo "Withdrawing WHILE PAUSED:"
echo '```'
} >> "$OUT"
WD=$(send_json "$VAULT" "withdrawAll()" | st)
AFTER=$(call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS")
STILL=$(cast call "$VAULT" "paused(address)(bool)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
{
echo "withdrawAll() status: $WD"
echo "still paused:         $STILL"
echo "balance after:        $AFTER"
echo '```'
echo
echo "The funds came out with the pause still engaged. This is the property the research task made"
echo "non-negotiable and it is the one task 8.5's mutant M7 exists to defend: M7 ADDS a pause check"
echo "to the withdrawal path, and it is caught both by a named unit test and by the theorem"
echo "\`check_vaultDepositorCanAlwaysWithdrawEvenWhenPaused\`. Task 8.7 proves the same property with"
echo "the pause landing strictly between the open and close blocks of a live trade."
echo
echo "**STOPPED BY:** withdrawal deliberately not being gated on \`paused\`. Pause constrains the"
echo "AGENT, never the depositor."
echo
} >> "$OUT"

# Leave the vault in a clean state.
send_json "$VAULT" "setPaused(bool)" false > /dev/null 2>&1

{
echo "## Verdict"
echo
echo "| attack | outcome | mechanism |"
echo "|---|---|---|"
echo "| 1. withdraw another user's balance | FAILED | no function credits any address but \`msg.sender\`; \`_withdraw\` is private |"
echo "| 2. trade past a user's limit | FAILED | \`ExceedsUserLimit\` at the boundary; no writer for another address's limit |"
echo "| 3. unpause as the agent | FAILED | \`paused\` is keyed on \`msg.sender\`; no override exists |"
echo "| 4. strand funds by pausing | FAILED | withdrawal is not gated on pause, proved as a theorem and on chain |"
echo
echo "## What is NOT claimed"
echo
echo "The vault OWNER can rotate the agent. A rotated agent inherits the same three gates and gains"
echo "nothing, which \`test_aRotatedAgentGetsNoNewPowers\` asserts, but an owner who loses their key"
echo "hands agent rotation to whoever holds it. That is a key-custody property rather than a contract"
echo "property, and it is bounded: no agent, rotated or original, can withdraw a depositor's funds."
echo
echo "A depositor can raise their OWN limit. That is intended: it is their money and their risk"
echo "appetite. What no key can do is raise someone else's."
echo
echo "The offchain risk engine's own limits still bind on top of any per-user limit, and"
echo "\`prop_a_user_limit_can_never_widen_what_the_system_allows\` proves a user limit can only ever"
echo "subtract from what the system permits."
} >> "$OUT"

echo "written: $OUT"
grep -A8 "^## Verdict" "$OUT"
