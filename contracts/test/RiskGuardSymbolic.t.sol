// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {RiskGuard} from "../src/RiskGuard.sol";

/// @title RiskGuardSymbolic
/// @notice Phase 3. These are not fuzz tests. Every `check_` function is proven
///         for ALL inputs in the declared ranges by a symbolic executor, so a
///         passing run means no counterexample exists rather than none was found.
///
/// The five invariants from ADR-006 are stated here as theorems.
contract RiskGuardSymbolic is Test {
    RiskGuard guard;
    address agent = address(0xA6E17);
    bytes32 constant M1 = keccak256("M1");
    bytes32 constant M2 = keccak256("M2");

    uint256 constant GROSS_CAP = 1_000 ether;
    uint256 constant MARKET_CAP = 400 ether;

    function setUp() public {
        guard = new RiskGuard(GROSS_CAP);
        guard.setAgent(agent, true);
        guard.setMarketCap(M1, MARKET_CAP);
        guard.setMarketCap(M2, MARKET_CAP);
    }

    /// Invariant 1 and 2. For ANY two exposure additions that succeed, no cap is
    /// exceeded. Symbolic over both amounts.
    function check_noSequenceOfAddsCanBreakACap(uint256 a, uint256 b) public {
        vm.assume(a > 0 && b > 0);
        vm.assume(a < 2 ** 96 && b < 2 ** 96);

        vm.prank(agent);
        try guard.addExposure(M1, a) {} catch {}
        vm.prank(agent);
        try guard.addExposure(M1, b) {} catch {}

        assert(guard.exposureOf(M1) <= MARKET_CAP);
        assert(guard.gross() <= GROSS_CAP);
    }

    /// Invariant 2 across two different markets, which is where a per-market-only
    /// check would pass while the book as a whole breached.
    function check_grossCapHoldsAcrossMarkets(uint256 a, uint256 b) public {
        vm.assume(a > 0 && b > 0);
        vm.assume(a < 2 ** 96 && b < 2 ** 96);

        vm.prank(agent);
        try guard.addExposure(M1, a) {} catch {}
        vm.prank(agent);
        try guard.addExposure(M2, b) {} catch {}

        assert(guard.gross() <= GROSS_CAP);
        assert(guard.exposureOf(M1) <= MARKET_CAP);
        assert(guard.exposureOf(M2) <= MARKET_CAP);
    }

    /// Invariant 3. Once killed, no addExposure can succeed, for any amount.
    function check_killedBlocksEveryAdd(uint256 amount) public {
        vm.assume(amount > 0 && amount < 2 ** 96);

        vm.prank(agent);
        guard.kill("symbolic");

        uint256 before = guard.exposureOf(M1);
        vm.prank(agent);
        try guard.addExposure(M1, amount) {
            // Reaching here means a killed guard accepted new exposure.
            assert(false);
        } catch {}
        assert(guard.exposureOf(M1) == before);
    }

    /// Invariant 4. No caller other than the owner can clear the kill switch.
    /// Symbolic over the caller address.
    function check_onlyOwnerCanRevive(address caller) public {
        vm.assume(caller != address(this));

        vm.prank(agent);
        guard.kill("symbolic");

        vm.prank(caller);
        try guard.revive() {
            assert(false);
        } catch {}
        assert(guard.killed());
    }

    /// Invariant 4, second half. No caller other than the owner can raise a cap,
    /// which is what makes "learning cannot widen a limit" structural.
    function check_onlyOwnerCanRaiseCaps(address caller, uint256 newCap) public {
        vm.assume(caller != address(this));

        vm.prank(caller);
        try guard.setMaxGross(newCap) {
            assert(false);
        } catch {}
        assert(guard.maxGross() == GROSS_CAP);
    }

    /// Invariant 5. The O(1) aggregate equals the O(n) recomputation after any
    /// add and reduce pair. This is the property that makes every cap check above
    /// meaningful, because a drifting aggregate silently invalidates all of them.
    function check_grossAlwaysEqualsSumOfParts(uint256 a, uint256 b, uint256 r) public {
        vm.assume(a < 2 ** 96 && b < 2 ** 96 && r < 2 ** 96);

        vm.prank(agent);
        try guard.addExposure(M1, a) {} catch {}
        vm.prank(agent);
        try guard.addExposure(M2, b) {} catch {}
        vm.prank(agent);
        try guard.reduceExposure(M1, r) {} catch {}

        assert(guard.gross() == guard.sumOfParts());
    }

    /// A market that was never configured must fail closed for any amount.
    function check_unconfiguredMarketAlwaysFailsClosed(bytes32 market, uint256 amount) public {
        vm.assume(market != M1 && market != M2);
        vm.assume(amount > 0 && amount < 2 ** 96);

        vm.prank(agent);
        try guard.addExposure(market, amount) {
            assert(false);
        } catch {}
        assert(guard.exposureOf(market) == 0);
    }
}
