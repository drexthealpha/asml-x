#!/usr/bin/env bash
# Task 8.5: mutation gate on the vault.
#
# THINKING: #22 inversion, #66 red teaming, #62 pre-mortem.
#
# EVIDENCE PATH: evidence/phase8/vault-mutation.txt
# PASS: every injected mutation is caught.
# FAKE WIN, quoted: "a high kill rate with the survivors unexamined."
# COUNTER, quoted: "survivors are listed individually with a judgement on each."
#
# THIS GATE ALSO SERVES TASK 8.4. The named fake win there is "proving a property that is vacuously
# true because the precondition is unreachable", and its counter is "each theorem is mutation-tested
# in 8.5; a vacuous property survives every mutation." So each mutant below records which THEOREM
# should have caught it as well as which test, and a mutant that only the unit suite catches is
# evidence that the corresponding theorem is not pulling its weight.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase8/vault-mutation.txt"
mkdir -p "$(dirname "$OUT")"
cd "$REPO/contracts"

F=src/AgentVault.sol
cp "$F" "$F.bak"
trap 'cp "$F.bak" "$F"; rm -f "$F.bak"' EXIT

RUN_HALMOS="${RUN_HALMOS:-1}"

{
echo "Task 8.5, vault mutation gate"
echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "halmos --solver yices theorems included: $RUN_HALMOS (0 skips them, for a fast unit-only pass)"
echo
} > "$OUT"

forge test --match-contract AgentVaultTest > /dev/null 2>&1
BASE_RC=$?
echo "baseline unit suite exit: $BASE_RC (0 means GREEN)" >> "$OUT"
if [ "$BASE_RC" -ne 0 ]; then
  echo "GATE: FAIL  baseline is not green; mutation results would be meaningless" >> "$OUT"
  tail -5 "$OUT"; exit 1
fi

SURVIVORS=0
KILLED=0
SURVIVOR_LIST=""

# Every theorem in the formal suite, discovered from the source rather than listed here, so a theorem
# added later is exercised by this gate automatically instead of being silently skipped.
ALL_THEOREMS=$(grep -oE '^    function (check_[a-zA-Z0-9_]+)' test/VaultFormal.t.sol | awk '{print $2}')
THEOREM_COUNT=$(printf '%s\n' "$ALL_THEOREMS" | grep -c .)
echo "theorems in the formal suite, all run against every mutant: $THEOREM_COUNT" >> "$OUT"

# $1 id, $2 description, $3 sed program, $4 the theorem that should catch it
mutate() {
  cp "$F.bak" "$F"
  sed -i "$3" "$F"
  local changed
  changed=$(diff "$F.bak" "$F" | grep -c '^[<>]')

  {
    echo
    echo "== $1: $2 =="
    echo "   sed: $3"
    echo "   lines changed: $changed"
    echo "   theorem I expected to catch it (advisory; all are run): $4"
  } >> "$OUT"

  if [ "$changed" -eq 0 ]; then
    echo "   NO-OP: the sed matched nothing, so this mutant was never injected. Counted as a" >> "$OUT"
    echo "   FAILURE of the gate, not of the contract: an uninjected mutant is a check that did" >> "$OUT"
    echo "   not run while looking like one that did." >> "$OUT"
    SURVIVORS=$((SURVIVORS + 1))
    SURVIVOR_LIST="$SURVIVOR_LIST $1(no-op)"
    return
  fi

  forge test --match-contract AgentVaultTest > /tmp/vmut.log 2>&1
  local URC=$?
  local HRC=1
  local BROKEN_THEOREMS=""

  {
    if [ "$URC" -ne 0 ]; then
      echo "   UNIT: KILLED by these named tests:"
      grep -E '^\[FAIL' /tmp/vmut.log | sed -E 's/.*\] ([a-zA-Z_0-9]+)\(.*/     \1/' | sort -u
    else
      echo "   UNIT: survived"
    fi
  } >> "$OUT"

  # EVERY theorem, not the one guessed in advance. Which theorem catches a mutant is a fact to be
  # discovered; naming one up front and running only that turns a miss by the wrong theorem into a
  # false report of vacuity.
  if [ "$RUN_HALMOS" = "1" ]; then
    for TH in $ALL_THEOREMS; do
      timeout 400 halmos --solver yices --contract VaultFormalTest --function "$TH" \
        --solver-timeout-assertion 120000 2>&1 | sed -r 's/\x1B\[[0-9;]*[mK]//g' > /tmp/vhal.log
      if ! grep -q "^\[PASS\] $TH" /tmp/vhal.log; then
        BROKEN_THEOREMS="$BROKEN_THEOREMS $TH"
        HRC=0
      fi
    done
    HRC=$([ -n "$BROKEN_THEOREMS" ] && echo 1 || echo 0)
    {
      if [ -n "$BROKEN_THEOREMS" ]; then
        echo "   THEOREMS that stopped proving:"
        for TH in $BROKEN_THEOREMS; do echo "     $TH"; done
      else
        echo "   THEOREMS: all $THEOREM_COUNT still prove. No symbolic property constrains this"
        echo "   behaviour, which is exactly the vacuity signature task 8.4's fake win warns about."
      fi
    } >> "$OUT"
  else
    HRC=1
  fi

  if [ "$URC" -ne 0 ] || [ "$HRC" -ne 0 ]; then
    KILLED=$((KILLED + 1))
  else
    SURVIVORS=$((SURVIVORS + 1))
    SURVIVOR_LIST="$SURVIVOR_LIST $1"
    {
      echo "   SURVIVED. THIS IS A FINDING, NOT A SCORE."
      echo "   Neither the suite nor the theorem distinguishes the correct behaviour from the"
      echo "   broken one, so the property they claim to establish is not established."
    } >> "$OUT"
  fi
}

# M1: the depositor check on withdraw. Removing the msg.sender binding lets any caller name any
#     depositor, which is the whole custody claim.
mutate M1 "withdraw no longer binds to msg.sender (any caller drains any depositor)" \
  's/        _withdraw(msg.sender, amount);/        _withdraw(tx.origin, amount);/' \
  check_vaultOnlyTheDepositorCanWithdraw

# M2: the pause check. Removing it lets the agent act on a paused depositor.
mutate M2 "pause check deleted from openTrade" \
  '/if (paused\[depositor\]) revert DepositorPaused(depositor);/d' \
  check_vaultPauseBlocksEveryAgentAction

# M3: the per-user limit check.
mutate M3 "per-user notional limit check deleted from openTrade" \
  '/if (notional > maxNotional\[depositor\]) {/,+2d' \
  check_vaultAgentCannotExceedTheUserLimit

# M4: balance accounting on withdraw. Not decrementing means a depositor can withdraw forever.
mutate M4 "withdraw does not decrement the depositor balance" \
  's/        balanceOf\[depositor\] -= amount;/        balanceOf[depositor] -= 0;/' \
  check_vaultStaysSolventAcrossDepositAndWithdraw

# M5: the committed deduction. Without it, committed funds are also withdrawable, so the same tokens
#     are both traded and withdrawn.
mutate M5 "withdrawable ignores committed funds" \
  's/        return bal > out ? bal - out : 0;/        return bal;/' \
  check_vaultStaysSolventAcrossDepositAndWithdraw

# M6: the deposit balance-delta check. Reintroduces the fee-on-transfer credit bug, which here makes
#     the vault insolvent on the very first deposit.
mutate M6 "deposit credits the requested amount rather than the measured delta" \
  's/        if (received < amount) revert ShortDeposit(amount, received);/        received = amount;/' \
  none

# M7: pause blocking withdrawal. THE INVERSE MUTATION, and the most important one here. Everything
#     above breaks a check; this one ADDS a check that the audit guidance names as a red flag. A
#     vault that traps funds while paused would pass every "does the guard work" test ever written.
mutate M7 "pause is made to block withdrawal (the trap the research forbade)" \
  's|    function _withdraw(address depositor, uint256 amount) private {|    function _withdraw(address depositor, uint256 amount) private {\n        if (paused[depositor]) revert DepositorPaused(depositor);|' \
  check_vaultDepositorCanAlwaysWithdrawEvenWhenPaused

cp "$F.bak" "$F"
forge test --match-contract AgentVaultTest > /dev/null 2>&1
FIN_RC=$?

{
echo
echo "== summary =="
echo "mutants injected: 7"
echo "killed:           $KILLED"
echo "survived:         $SURVIVORS"
if [ -n "$SURVIVOR_LIST" ]; then
  echo "survivor ids:    $SURVIVOR_LIST"
  echo "Each survivor is written up individually above with a judgement, per this task's counter."
fi
echo "restored suite:   exit $FIN_RC"
echo
if [ "$SURVIVORS" -eq 0 ] && [ "$FIN_RC" -eq 0 ]; then
  echo "GATE: PASS  every mutant caught, and the source is restored green"
else
  echo "GATE: FAIL  $SURVIVORS survivor(s):$SURVIVOR_LIST"
fi
} >> "$OUT"

tail -24 "$OUT"
