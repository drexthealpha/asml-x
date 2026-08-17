#!/usr/bin/env bash
# Task 7.5: mutation gate on the fee itself.
#
# THINKING: #22 inversion, #66 red teaming, #29 margin-of-safety.
#
# EVIDENCE PATH: evidence/phase7/fee-mutation.txt
# PASS: every injected mutation is caught by a NAMED test.
#
# The named fake win: "mutating something no test covers and reporting the suite still passes as
# success." The counter, quoted: "a surviving mutant is a FINDING and must be listed, not summarised
# into a score." So this script prints the mutant source line, the tests that caught it BY NAME, and
# writes a FINDINGS section for any survivor rather than a percentage.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase7/fee-mutation.txt"
mkdir -p "$(dirname "$OUT")"
cd "$REPO/contracts"

F=src/FeeCollector.sol
cp "$F" "$F.bak"
trap 'cp "$F.bak" "$F"; rm -f "$F.bak"' EXIT

SUITE='test/{FeeCollector,FeeBypass,Venue}.t.sol'

{
  echo "Task 7.5, fee mutation gate"
  echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
} > "$OUT"

forge test --match-path "$SUITE" > /tmp/base.log 2>&1
BASE_RC=$?
BASE_N=$(grep -c '^\[PASS\]' /tmp/base.log)
echo "baseline: exit $BASE_RC, $BASE_N tests passing" >> "$OUT"
if [ "$BASE_RC" -ne 0 ]; then
  echo "GATE: FAIL  baseline is not green, mutation results would be meaningless" >> "$OUT"
  tail -20 "$OUT"; exit 1
fi

SURVIVORS=0
KILLED=0

# $1 = mutant id, $2 = description, $3 = sed program
mutate() {
  cp "$F.bak" "$F"
  sed -i "$3" "$F"
  {
    echo
    echo "== $1: $2 =="
    echo "-- edit applied --"
    echo "   sed: $3"
    echo "   lines changed: $(diff "$F.bak" "$F" | grep -c '^[<>]')"
  } >> "$OUT"

  forge test --match-path "$SUITE" > /tmp/mut.log 2>&1
  RC=$?
  if [ "$RC" -ne 0 ]; then
    KILLED=$((KILLED + 1))
    {
      echo "-- KILLED, caught by these named tests --"
      grep -E '^\[FAIL' /tmp/mut.log | sed -E 's/.*\] ([a-zA-Z_0-9]+)\(.*/   \1/' | sort -u
    } >> "$OUT"
  else
    SURVIVORS=$((SURVIVORS + 1))
    {
      echo "-- SURVIVED. THIS IS A FINDING, NOT A SCORE. --"
      echo "   The suite stayed green with this mutation in place, which means no test"
      echo "   distinguishes the correct behaviour from the broken one."
    } >> "$OUT"
  fi
}

# M1 wrong divisor: 10000 -> 1000, a 10x overcharge.
mutate M1 "fee divisor 10_000 -> 1_000 (10x overcharge)" \
  's/uint256 public constant BPS_DENOMINATOR = 10_000;/uint256 public constant BPS_DENOMINATOR = 1_000;/'

# M2 ceiling check removed from the CONSTRUCTOR, which is where it is reachable.
#
# This mutant originally targeted the identical check inside setFeeBps and SURVIVED. That survivor was
# recorded as a finding and acted on: the setFeeBps copy was unreachable dead code, because the
# can-only-lower check below it already forces newBps < feeBps and the constructor already forces
# feeBps <= MAX_FEE_BPS. It was deleted from the contract rather than covered by a test that could
# never reach it. The constructor is the reachable site and is what this mutant now breaks.
mutate M2 "ceiling check deleted from the constructor" \
  '/if (feeBps_ > MAX_FEE_BPS) revert FeeAboveCeiling(feeBps_, MAX_FEE_BPS);/d'

# M3 one-directional check removed: the fee becomes raisable.
mutate M3 "can-only-lower check deleted from setFeeBps" \
  '/if (newBps >= feeBps) revert FeeNotLowered(feeBps, newBps);/d'

# M4 stale value in the event: emits the notional where the fee amount belongs, so the dashboard
# reports a number 200x too large while every balance is still correct.
mutate M4 "FeeCharged emits notional in place of feeAmount" \
  's/emit FeeCharged(payer, market, token, notional, feeAmount, cachedBps);/emit FeeCharged(payer, market, token, notional, notional, cachedBps);/'

# M5 balance-delta check removed: the Cudos failure, reintroduced.
mutate M5 "ShortPay balance-delta check deleted" \
  '/if (received < feeAmount) revert ShortPay(feeAmount, received);/d'

# M6 charger check removed: anyone could emit fee events and inflate the growth counter.
mutate M6 "charger authorisation deleted from charge()" \
  '/if (!chargers\[msg.sender\]) revert NotCharger();/d'

cp "$F.bak" "$F"
forge test --match-path "$SUITE" > /tmp/fin.log 2>&1
FIN_RC=$?

{
  echo
  echo "== summary =="
  echo "mutants injected: 6"
  echo "killed:           $KILLED"
  echo "survived:         $SURVIVORS"
  echo "restored suite:   exit $FIN_RC"
  echo
  if [ "$SURVIVORS" -eq 0 ] && [ "$FIN_RC" -eq 0 ]; then
    echo "GATE: PASS  every mutant was caught by a named test and the source is restored green"
  else
    echo "GATE: FAIL  $SURVIVORS surviving mutant(s) listed above as findings"
  fi
} >> "$OUT"

tail -22 "$OUT"
