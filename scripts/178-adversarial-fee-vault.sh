#!/usr/bin/env bash
# Task 15.1: adversarial audit of the DEPLOYED fee and vault surfaces.
#
# THINKING: #66 red teaming (probe what a stranger actually reaches, not what the tests already
# cover), #7 is-this-real, #62 margin of safety (the property is not "each call reverts" but "there
# is no ordering of calls that gets money out").
#
# EVIDENCE PATH: evidence/phase15/adversarial-fee-vault.md
# PASS: every hostile call is refused by the DEPLOYED BYTECODE with a named error, and the negative
# control succeeds, without which a contract that reverted on everything would pass.
#
# WHY eth_call WITH --from AND NOT A SECOND FUNDED KEY. `cast call --from` makes the node execute the
# real deployed bytecode with an arbitrary `msg.sender`. That is exactly the question an access
# control audit asks, it costs nothing, and it needs no second keystore. What it does NOT test is
# anything depending on the attacker holding a balance, so the cases below are chosen to be ones
# where authorisation, not funding, is the gate. Cases that need funds are named as not covered
# rather than quietly skipped.
#
# WHY THIS IS NOT ALREADY COVERED BY THE FOUNDRY TESTS. Those run against locally compiled bytecode.
# This runs against what is actually deployed at the addresses the dashboard links to. A contract can
# pass its own test suite and not be the contract that got deployed.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

RPC="$XLAYER_TESTNET_RPC"
OUT="$REPO/evidence/phase15/adversarial-fee-vault.md"
mkdir -p "$(dirname "$OUT")"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
VAULT=$(a agentVault); FEE=$(a feeCollector); QUOTE=$(a tQUOTE)

# A stranger. Not a key this project holds: an address chosen so it cannot be the owner, the agent
# or a charger by accident.
EVE=0x00000000000000000000000000000000000000Ee

PASS=0; FAIL=0
ROWS=""

CAST="$HOME/.foundry/bin/cast"

# MATCHES ON THE ERROR SELECTOR, NOT ITS NAME. An X Layer node returns custom-error reverts as raw
# calldata: `execution reverted, data: "0x30cd7471"`, with no name anywhere in the response. The
# first version of this script grepped for the name, every case reported FAIL, and the negative
# controls passed, which is the pattern that says the MATCH is wrong rather than the contract.
#
# Matching the selector is also the stronger claim. "It reverted" and "it reverted for the reason I
# said it would" are different findings, and only the second one is an access-control result: a
# revert on a bad allowance and a revert on a missing role look identical to a name-free grep.
#
# The selector is computed from the signature by `cast sig` at run time rather than pasted in, so a
# renamed error cannot leave a stale hex constant silently matching nothing.
probe() { # label error_signature target sig args...
  local label="$1" errsig="$2" target="$3" sig="$4"; shift 4
  local sel out rc verdict got
  sel=$("$CAST" sig "$errsig")
  out=$("$CAST" call "$target" "$sig" "$@" --from "$EVE" --rpc-url "$RPC" 2>&1) && rc=0 || rc=1
  if [ "$rc" -eq 0 ]; then
    verdict=FAIL; got="RETURNED, NOT REFUSED"; FAIL=$((FAIL + 1))
  elif echo "$out" | grep -q "$sel"; then
    verdict=PASS; got="$sel"; PASS=$((PASS + 1))
  else
    verdict=FAIL; got="reverted, but not with $sel: $(echo "$out" | grep -oE '0x[0-9a-f]{8}' | head -1)"
    FAIL=$((FAIL + 1))
  fi
  printf "  %-46s %-38s %s\n" "$label" "$errsig $sel" "$verdict"
  ROWS="$ROWS| \`$label\` | \`$errsig\` = \`$sel\` | $got | $verdict |
"
}

echo "=== attacker: $EVE ==="
echo "=== vault $VAULT ==="
echo
printf "  %-46s %-38s %s\n" "case" "expected error and selector" "verdict"

# --- AgentVault: the money-moving surface.
probe "eve opens a trade on someone else's deposit" "NotAgent()" \
  "$VAULT" "openTrade(address,uint256)" "$DEPLOYER_ADDRESS" 1000000
probe "eve closes a trade" "NotAgent()" \
  "$VAULT" "closeTrade(address,uint256,uint256)" "$DEPLOYER_ADDRESS" 1000000 1000000
probe "eve reassigns the agent to herself" "NotOwner()" \
  "$VAULT" "setAgent(address)" "$EVE"
probe "eve withdraws from an empty balance" "InsufficientBalance(uint256,uint256)" \
  "$VAULT" "withdraw(uint256)" 1000000
probe "eve deposits zero" "ZeroAmount()" \
  "$VAULT" "deposit(uint256,uint256)" 0 1000000

# --- FeeCollector: the revenue surface.
probe "eve charges a fee, minting revenue" "NotCharger()" \
  "$FEE" "charge(address,bytes32,address,uint256)" "$DEPLOYER_ADDRESS" \
  0x0000000000000000000000000000000000000000000000000000000000000001 "$QUOTE" 1000000
probe "eve raises the fee rate" "NotOwner()" \
  "$FEE" "setFeeBps(uint256)" 9999
probe "eve points the treasury at herself" "NotOwner()" \
  "$FEE" "setTreasury(address)" "$EVE"
probe "eve authorises herself as a charger" "NotOwner()" \
  "$FEE" "setCharger(address,bool)" "$EVE" true

echo
echo "=== negative controls: calls that MUST succeed ==="
CTRL_OK=0; CTRL_N=0
ctrl() { # label target sig args...
  local label="$1" target="$2" sig="$3"; shift 3
  local out
  CTRL_N=$((CTRL_N + 1))
  if out=$("$CAST" call "$target" "$sig" "$@" --from "$EVE" --rpc-url "$RPC" 2>&1); then
    printf "  %-46s %s\n" "$label" "ok: $(echo "$out" | head -1 | cut -c1-40)"
    CTRL_OK=$((CTRL_OK + 1))
    ROWS="$ROWS| \`$label\` | succeeds | $(echo "$out" | head -1 | cut -c1-40) | CONTROL |
"
  else
    printf "  %-46s %s\n" "$label" "UNEXPECTEDLY REVERTED"
    ROWS="$ROWS| \`$label\` | succeeds | REVERTED | CONTROL-FAIL |
"
  fi
}
# TYPED return signatures, so the row shows a DECODED value. The first version called these
# untyped and printed raw 32-byte words truncated to 40 characters for the table, which cuts off the
# last word: a solvency check reading `false` would have displayed identically to one reading `true`.
# An evidence file whose formatting can hide the answer is worse than no evidence file.
ctrl "anyone may read the fee quote" "$FEE" "quoteFee(uint256)(uint256)" 1000000
ctrl "anyone may read vault solvency" "$VAULT" "isSolvent()(bool)"
ctrl "anyone may read a withdrawable balance" "$VAULT" "withdrawable(address)(uint256)" "$DEPLOYER_ADDRESS"

VERDICT=FAIL
if [ "$FAIL" -eq 0 ] && [ "$PASS" -ge 9 ] && [ "$CTRL_OK" -eq "$CTRL_N" ]; then VERDICT=PASS; fi

{
echo "# Task 15.1: adversarial audit of the deployed fee and vault surfaces"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **$VERDICT**"
echo
echo "Chain 1952. Vault \`$VAULT\`, FeeCollector \`$FEE\`."
echo "Attacker \`$EVE\`, an address this project holds no key for, chosen so it cannot be the owner,"
echo "the agent or a charger by accident."
echo
echo "## Why this is not what the Foundry tests already do"
echo
echo "Those run against locally compiled bytecode. **This runs against what is actually deployed** at"
echo "the addresses the dashboard links to. A contract can pass its own suite and not be the contract"
echo "that reached the chain."
echo
echo "\`cast call --from\` makes the node execute the deployed bytecode with a hostile \`msg.sender\`,"
echo "which is precisely the question an access-control audit asks, at zero cost and with no second"
echo "keystore. Its limit is stated below rather than left implicit."
echo
echo "## Results"
echo
echo "| call as the attacker | expected | got | verdict |"
echo "|---|---|---|---|"
printf "%s" "$ROWS"
echo
echo "$PASS refused as expected, $FAIL unexpected, $CTRL_OK of $CTRL_N controls succeeded."
echo
echo "## The controls are the part that makes the refusals mean anything"
echo
echo "A contract that reverted on every call would score a perfect refusal rate. The three reads"
echo "above are executed as the SAME attacker address and succeed, so the refusals are the access"
echo "control working rather than the contract being broken or the address being wrong."
echo
echo "## What this does NOT cover, stated rather than skipped"
echo
echo "1. **Cases where funding, not authorisation, is the gate.** The attacker holds no balance, so"
echo "   \`deposit\` with a real amount cannot be distinguished here between refusal for want of an"
echo "   allowance and refusal by policy. Those paths are covered by the invariant campaign in 14.2,"
echo "   which reaches them with funded handlers."
echo "2. **Reentrancy.** Not reachable through \`eth_call\` from an EOA, since it needs a hostile"
echo "   contract. The transient-storage guards are covered by the Foundry suite."
echo "3. **The owner turning hostile.** Owner-authorised calls are refused for the attacker and would"
echo "   succeed for the owner, which is the design. What limits owner power is that pause can never"
echo "   block withdrawal, proved as an invariant in 14.2, not an access check here."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/178-adversarial-fee-vault.sh"
echo '```'
} > "$OUT"

echo
echo "written: $OUT"
echo "VERDICT: $VERDICT  (refused $PASS, unexpected $FAIL, controls $CTRL_OK/$CTRL_N)"
[ "$VERDICT" = PASS ]
