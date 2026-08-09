// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {RwaVault} from "../src/RwaVault.sol";
import {RwaRiskGuard} from "../src/RwaRiskGuard.sol";

/// @title RwaRiskGuardSymbolic
/// @notice Phase 5 formal verification. Each `check_` function is proven for ALL
///         inputs in the declared ranges, so a pass means no counterexample exists.
///
/// Deliberately proven WITHOUT vm.warp: time-dependent properties are covered by the
/// concrete tests in Rwa.t.sol, and keeping the symbolic set time-free avoids
/// depending on cheatcode support that may differ between prover versions. That
/// limitation is stated rather than hidden, and the two suites together cover all
/// four refusals.
contract RwaRiskGuardSymbolic is Test {
    RwaVault vault;
    RwaRiskGuard guard;
    address agent = address(0xA6E17);
    bytes32 constant M = keccak256("RWA/tQUOTE");

    uint256 constant CAP = 400 ether;
    uint256 constant GROSS = 1_000 ether;
    uint256 constant MAX_DIV_BPS = 300;

    function setUp() public {
        vault = new RwaVault(1e18, 0, 0); // windowPeriod 0 means always redeemable
        guard = new RwaRiskGuard(GROSS, address(vault), type(uint256).max, 0, MAX_DIV_BPS);
        guard.setAgent(agent, true);
        guard.setMarketCap(M, CAP);
    }

    /// A paused issuer refuses new exposure for ANY amount.
    function check_pausedRefusesEveryAmount(uint256 amount) public {
        vm.assume(amount > 0 && amount < 2 ** 96);
        vault.setPaused(true);

        uint256 before = guard.exposureOf(M);
        vm.prank(agent);
        try guard.addExposure(M, amount) {
            assert(false); // a paused instrument must never accept new exposure
        } catch {}
        assert(guard.exposureOf(M) == before);
    }

    /// De-risking succeeds for ANY amount up to the held position, no matter what
    /// the RWA conditions say. This is the asymmetry that keeps a risk control from
    /// becoming a trap.
    function check_reduceIsNeverBlockedByRwaConditions(uint256 add, uint256 cut) public {
        vm.assume(add > 0 && add <= CAP);
        vm.assume(cut > 0 && cut <= add);

        vm.prank(agent);
        guard.addExposure(M, add);

        // Turn on every refusal condition available without moving time.
        vault.setPaused(true);
        vm.prank(agent);
        guard.observeMarketPrice(1_000_000e18); // enormous divergence

        assert(!guard.rwaTradeableFlag()); // adding is refused

        vm.prank(agent);
        guard.reduceExposure(M, cut); // and yet exiting works
        assert(guard.exposureOf(M) == add - cut);
    }

    /// Divergence beyond tolerance refuses, within tolerance permits. Symbolic over
    /// the observed price, so the boundary is proven rather than sampled.
    function check_divergenceBoundaryIsExact(uint256 observed) public {
        vm.assume(observed > 0 && observed < 100e18);
        vm.prank(agent);
        guard.observeMarketPrice(observed);

        uint256 div = guard.divergenceBps();
        bool ok = guard.rwaTradeableFlag();

        if (div > MAX_DIV_BPS) {
            assert(!ok);
        } else {
            assert(ok);
        }
    }

    /// The inherited cap theorem still holds through the subclass. If overriding
    /// addExposure had bypassed the cap arithmetic, this is what would catch it.
    function check_inheritedCapsSurviveTheOverride(uint256 a, uint256 b) public {
        vm.assume(a > 0 && b > 0);
        vm.assume(a < 2 ** 96 && b < 2 ** 96);

        vm.prank(agent);
        try guard.addExposure(M, a) {} catch {}
        vm.prank(agent);
        try guard.addExposure(M, b) {} catch {}

        assert(guard.exposureOf(M) <= CAP);
        assert(guard.gross() <= GROSS);
        assert(guard.gross() == guard.sumOfParts());
    }

    /// The kill switch still stops the RWA path for any amount.
    function check_killedRefusesEveryAmountOnTheRwaPath(uint256 amount) public {
        vm.assume(amount > 0 && amount < 2 ** 96);
        vm.prank(agent);
        guard.kill("symbolic");

        uint256 before = guard.exposureOf(M);
        vm.prank(agent);
        try guard.addExposure(M, amount) {
            assert(false);
        } catch {}
        assert(guard.exposureOf(M) == before);
    }

    /// No caller other than the owner can loosen the RWA policy. Symbolic over the
    /// caller, which is what makes "learning cannot widen a limit" structural on this
    /// path too.
    function check_onlyOwnerCanLoosenTheRwaPolicy(address caller, uint256 newAge) public {
        vm.assume(caller != address(this));
        uint256 beforeAge = guard.maxOracleAge();

        vm.prank(caller);
        try guard.setRwaPolicy(newAge, 0, MAX_DIV_BPS) {
            assert(false);
        } catch {}
        assert(guard.maxOracleAge() == beforeAge);
    }

    /// The yield index can never fall, for any pair of values.
    function check_yieldIndexIsMonotonic(uint256 first, uint256 second) public {
        vm.assume(first >= 1e18 && first < 100e18);
        vm.assume(second < 100e18);

        vault.accrueYield(first);
        uint256 afterFirst = vault.yieldIndex();

        try vault.accrueYield(second) {
            assert(second >= afterFirst);
        } catch {
            assert(second < afterFirst);
        }
        assert(vault.yieldIndex() >= afterFirst);
    }
}
