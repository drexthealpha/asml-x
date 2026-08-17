#!/usr/bin/env bash
# Task 1.5 scribble. Instrument one property, then prove the assertion actually FIRES on a
# violating input and stays quiet on a valid one.
#
# THINKING: #41 algorithmic (a scribble annotation compiles to a runtime assertion, so the
# artifact is instrumented source plus an observed revert), #22 inversion (an instrumented
# contract that never reverts proves nothing, so the violating input is the real test),
# #50 empirical.
#
# EVIDENCE PATH declared before code: evidence/phase0/scribble.txt
# PASS: the instrumented contract REVERTS on the violating input and PASSES on the valid
# one. A successful instrumentation run alone is not a pass, because instrumentation that
# emits an assertion nobody triggers is the phase's named fake win.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="/home/zulab/.npm-global/bin:/home/zulab/.foundry/bin:$PATH"

OUT="$REPO/evidence/phase0/scribble.txt"
mkdir -p "$(dirname "$OUT")"
SRC="$REPO/contracts/scribble/CapAccumulator.sol"
INST="$REPO/contracts/scribble/CapAccumulator.instrumented.sol"

{
echo "scribble instrument-and-fire test, task 1.5"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Tool"
echo "  scribble: $(scribble --version 2>&1 | head -1)"
echo "  package:  eth-scribble (verified npmjs.com/package/eth-scribble)"
echo
echo "## Target and the annotated property"
echo "  file: contracts/scribble/CapAccumulator.sol"
grep -n 'if_succeeds' "$SRC" | sed 's/^/    /'
echo
echo "  This is RiskGuard's per-market cap invariant reduced to its smallest form."
echo "  RiskGuard itself is NOT instrumented: scribble rewrites source, and the deployed"
echo "  bytecode is what every onchain claim rests on."
echo

echo "## Instrumenting"
cd "$REPO/contracts/scribble"
# --instrumentation-metadata-file is required, and scribble said so itself:
# "Unable to detect project root to place instrumentation metadata file."
# The tool named the fix, so this is not a guess.
if scribble CapAccumulator.sol --output-mode files \
     --output CapAccumulator.instrumented.sol \
     --instrumentation-metadata-file scribble-metadata.json 2>&1 | tail -6; then
  echo "  instrumentation exit 0"
else
  echo "  instrumentation reported a non-zero exit, output above"
fi

# In `--output-mode files` scribble writes `<name>.sol.instrumented` NEXT TO the source and
# ignores --output, which applies to its single-file modes. Its own log line said so:
#   "CapAccumulator.sol -> CapAccumulator.sol.instrumented"
# Solidity needs a .sol extension to import, so give the artifact one.
if [ -f "$REPO/contracts/scribble/CapAccumulator.sol.instrumented" ]; then
  cp "$REPO/contracts/scribble/CapAccumulator.sol.instrumented" "$INST"
  echo "  renamed CapAccumulator.sol.instrumented to CapAccumulator.instrumented.sol"
fi

if [ -f "$INST" ]; then
  echo
  echo "## Proof the annotation became a real runtime check"
  echo "  instrumented file: $(stat -c%s "$INST") bytes"
  echo "  assertion machinery emitted into the source:"
  grep -cE '__ScribbleUtilsLib|AssertionFailed|_original_' "$INST" 2>/dev/null | sed 's/^/    matches: /'
  grep -nE 'AssertionFailed|emit AssertionFailed' "$INST" 2>/dev/null | head -4 | sed 's/^/    /'
else
  echo "  NO instrumented output produced"
fi
} 2>&1 | tee "$OUT"

echo | tee -a "$OUT"
echo "## Does the assertion FIRE? Violating vs valid input" | tee -a "$OUT"

# The violating input overflows the cap; the valid one stays under it. Run both against the
# instrumented contract through forge so the revert is observed, not assumed.
cat > "$REPO/contracts/test/ScribbleFire.t.sol" <<'SOL'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CapAccumulator} from "../scribble/CapAccumulator.instrumented.sol";
import {CapAccumulator as PlainAccumulator} from "../scribble/CapAccumulator.sol";

/// Task 1.5 counter-test: an instrumented contract that never reverts proves nothing.
///
/// The decisive test is `test_theRevertComesFromInstrumentationNotArithmetic`. Passing
/// `vm.expectRevert()` on the instrumented contract alone would not tell us WHY it
/// reverted. Running the SAME input against the un-instrumented original, and seeing it
/// succeed, is what proves the scribble assertion is doing the work.
contract ScribbleFireTest is Test {
    CapAccumulator acc;
    PlainAccumulator plain;

    function setUp() public {
        acc = new CapAccumulator(100);
        plain = new PlainAccumulator(100);
    }

    function test_validInputPasses() public {
        acc.add(50);
        assertEq(acc.total(), 50);
    }

    function test_violatingInputTripsTheAssertion() public {
        // 150 exceeds the cap of 100. No arithmetic overflow is involved: 0 + 150 fits in
        // uint256 comfortably. The only thing that can stop this is the annotation.
        vm.expectRevert();
        acc.add(150);
    }

    /// The break-attempt. Same input, un-instrumented contract, must SUCCEED.
    /// If this also reverted, the previous test would be proving arithmetic, not scribble.
    function test_theRevertComesFromInstrumentationNotArithmetic() public {
        plain.add(150);
        assertEq(plain.total(), 150, "the plain contract has no cap check, so 150 stands");
    }

    /// A CUMULATIVE breach, which a single-call check would miss. 50 then 60 is 110 > 100.
    function test_cumulativeBreachAlsoTrips() public {
        acc.add(50);
        vm.expectRevert();
        acc.add(60);
    }

    /// And a cumulative total that stays under the cap must not trip.
    function test_cumulativeUnderCapDoesNotTrip() public {
        acc.add(50);
        acc.add(40);
        assertEq(acc.total(), 90);
    }
}
SOL

cd "$REPO/contracts"
forge build --ast >/dev/null 2>&1
forge test --match-contract ScribbleFireTest -vv 2>&1 | tail -20 | tee -a "$OUT"

{
echo
echo "## Verdict, task 1.5"
echo "  PASS requires BOTH: the valid input succeeds AND the violating input reverts."
echo "  A green instrumentation run on its own is the fake win this phase names."
} | tee -a "$OUT"

echo "written: $OUT"
