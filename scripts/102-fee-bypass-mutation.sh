#!/usr/bin/env bash
# R-MUTATE for task 7.3. A test that cannot fail is deleted.
#
# Two mutations, one per bypass, each removing exactly the line that closes it:
#   M1: delete the authorised-taker check in OrderBookVenue.take   -> bypass A reopens
#   M2: delete the last-leg-must-be-fee-collector check in BatchExecutor -> bypass B reopens
#
# PASS requires BOTH to turn the suite RED, and the restored source to return to GREEN. A mutation
# that leaves the suite green means the enforcement is untested and the 7.3 claim is decoration.
#
# EVIDENCE PATH: evidence/phase7/fee-bypass-mutation.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase7/fee-bypass-mutation.txt"
mkdir -p "$(dirname "$OUT")"
cd "$REPO/contracts"

VENUE=src/OrderBookVenue.sol
EXECF=src/BatchExecutor.sol
cp "$VENUE" "$VENUE.bak"
cp "$EXECF" "$EXECF.bak"

restore() {
  cp "$VENUE.bak" "$VENUE"
  cp "$EXECF.bak" "$EXECF"
  rm -f "$VENUE.bak" "$EXECF.bak"
}
trap restore EXIT

run_suite() {
  forge test --match-path 'test/{FeeBypass,Venue}.t.sol' 2>&1 | tail -3
}

{
  echo "Task 7.3 mutation gate"
  echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  echo "== baseline, unmutated =="
  run_suite
  BASE_RC=${PIPESTATUS[0]:-0}
} > "$OUT" 2>&1

forge test --match-path 'test/{FeeBypass,Venue}.t.sol' > /dev/null 2>&1
BASE_RC=$?
echo "baseline exit: $BASE_RC (0 means GREEN)" >> "$OUT"

# ---- M1: reopen the direct-venue bypass
sed -i '/if (!authorisedTakers\[msg.sender\]) revert NotAuthorisedTaker(msg.sender);/d' "$VENUE"
{
  echo
  echo "== M1: authorised-taker check DELETED from OrderBookVenue.take =="
  run_suite
} >> "$OUT" 2>&1
forge test --match-path 'test/{FeeBypass,Venue}.t.sol' > /dev/null 2>&1
M1_RC=$?
echo "M1 exit: $M1_RC (non-zero means RED, which is the pass)" >> "$OUT"
cp "$VENUE.bak" "$VENUE"

# ---- M2: reopen the missing-fee-leg bypass
python3 - "$EXECF" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(
    r"\n *if \(legs\[legs\.length - 1\]\.target != feeCollector\) \{\n.*?\n *\}\n",
    "\n",
    s,
    flags=re.S,
)
open(p, "w").write(s)
PY
{
  echo
  echo "== M2: last-leg-must-be-fee-collector check DELETED from BatchExecutor =="
  run_suite
} >> "$OUT" 2>&1
forge test --match-path 'test/{FeeBypass,Venue}.t.sol' > /dev/null 2>&1
M2_RC=$?
echo "M2 exit: $M2_RC (non-zero means RED, which is the pass)" >> "$OUT"

restore
trap - EXIT

{
  echo
  echo "== restored =="
  run_suite
} >> "$OUT" 2>&1
forge test --match-path 'test/{FeeBypass,Venue}.t.sol' > /dev/null 2>&1
FIN_RC=$?
echo "restored exit: $FIN_RC (0 means GREEN again)" >> "$OUT"

{
  echo
  if [ "$BASE_RC" -eq 0 ] && [ "$M1_RC" -ne 0 ] && [ "$M2_RC" -ne 0 ] && [ "$FIN_RC" -eq 0 ]; then
    echo "GATE: PASS  both enforcement lines are load-bearing"
  else
    echo "GATE: FAIL  base=$BASE_RC m1=$M1_RC m2=$M2_RC restored=$FIN_RC"
  fi
} >> "$OUT"

tail -32 "$OUT"
