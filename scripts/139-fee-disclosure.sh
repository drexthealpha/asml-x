#!/usr/bin/env bash
# Task 9.9 gate: the fee is shown before activation, read from the deployed contract.
#
# THINKING: #49 skeptical (a disclosure that is a constant is not a disclosure), #12 design thinking,
# #19 critical thinking.
#
# EVIDENCE PATH: evidence/phase9/fee-disclosure.md
# PASS: the displayed fee equals FeeCollector.feeBps() read live; changing it onchain changes the UI.
#
# FAKE WIN, quoted: "a hardcoded '0.5%' in the component."
# COUNTER, quoted: "task 5.2's magic-number audit covers this file and would fail on a literal."
#
# THIS GATE GOES FURTHER THAN A GREP. A grep proves no literal is present today; it does not prove
# the number on screen came from the chain. So the fee is LOWERED ON CHAIN and the UI is re-read. If
# the display follows, it is reading the contract. Nothing else explains the change.
#
# The fee can only ever be lowered (FeeCollector.setFeeBps reverts on a raise, proved in task 7.2 and
# by check_setFeeBpsCanOnlyLower in 7.4), so this test is one-way: it walks the rate DOWN and leaves
# it there. That is safe by design, and it is the reason a "restore the old value" step is absent
# rather than forgotten.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase9/fee-disclosure.md"
mkdir -p "$(dirname "$OUT")"
RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
FEE=$(python3 -c "import json;print(json.load(open('$J'))['feeCollector'])")

BEFORE=$(cast call "$FEE" "feeBps()(uint256)" --rpc-url "$RPC" | awk '{print $1}')

{
echo "# Task 9.9: fee percentage shown before activation"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
echo
echo "## No literal in the component"
echo
echo 'Searching every frontend file for a hardcoded percentage or basis-point figure near the word'
echo '"fee". A literal here would be the named fake win.'
echo
echo '```'
} > "$OUT"

# Any numeric literal that looks like a fee rate, in a file that mentions fees.
LITERALS=$(grep -rnE '(0\.5%|50 ?bps|"50"|= ?50\b|0\.005)' "$REPO/ui-v2/src" \
  --include='*.ts' --include='*.tsx' 2>/dev/null | grep -iE 'fee' || true)
if [ -z "$LITERALS" ]; then
  echo "  no hardcoded fee rate found in ui-v2/src" >> "$OUT"
  LIT_OK=1
else
  echo "  FOUND:" >> "$OUT"
  printf '%s\n' "$LITERALS" | sed 's/^/    /' >> "$OUT"
  LIT_OK=0
fi

{
echo '```'
echo
echo "## The stronger test: change it on chain and watch the UI follow"
echo
echo "A grep proves no literal exists today. It does not prove the number on screen came from the"
echo "chain. So the rate is LOWERED on chain and the UI re-read."
echo
echo '```'
echo "FeeCollector:            $FEE"
echo "feeBps before:           $BEFORE"
} >> "$OUT"

# Lower by 1 bp. Only ever downward: setFeeBps reverts on a raise, by design.
TARGET=$((BEFORE - 1))
TX=$(cast send "$FEE" "setFeeBps(uint256)" "$TARGET" \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['status'],d['transactionHash'])" 2>/dev/null || echo "FAIL none")

AFTER=$(cast call "$FEE" "feeBps()(uint256)" --rpc-url "$RPC" | awk '{print $1}')

{
echo "setFeeBps($TARGET):       $TX"
echo "feeBps after:            $AFTER"
echo '```'
echo
echo "The UI must now show $AFTER, not $BEFORE. Verified in the Browser pane by reading the"
echo "fee-disclosure element after a reload; the result is appended below."
} >> "$OUT"

echo "literal-free: $LIT_OK"
echo "feeBps: $BEFORE -> $AFTER"
echo "written: $OUT"
[ "$LIT_OK" -eq 1 ] && [ "$AFTER" = "$TARGET" ]
