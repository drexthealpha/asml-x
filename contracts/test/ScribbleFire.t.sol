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
