// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {RwaVault} from "../src/RwaVault.sol";
import {RwaRiskGuard} from "../src/RwaRiskGuard.sol";
import {RiskGuard} from "../src/RiskGuard.sol";

contract RwaTest is Test {
    RwaVault vault;
    RwaRiskGuard guard;
    address agent = address(0xA6E17);
    bytes32 constant RWA_MARKET = keccak256("RWA/tQUOTE");

    uint256 constant MAX_ORACLE_AGE = 3600; // 1 hour
    uint256 constant WINDOW_PERIOD = 7 days;
    uint256 constant WINDOW_LENGTH = 1 days;
    uint256 constant WINDOW_BUFFER = 12 hours;
    uint256 constant MAX_DIVERGENCE_BPS = 300; // 3 percent

    function setUp() public {
        // Start well clear of an epoch boundary so window arithmetic is unambiguous.
        vm.warp(1_000_000);
        vault = new RwaVault(1e18, WINDOW_PERIOD, WINDOW_LENGTH);
        guard = new RwaRiskGuard(
            1_000 ether,
            address(vault),
            MAX_ORACLE_AGE,
            WINDOW_BUFFER,
            MAX_DIVERGENCE_BPS
        );
        guard.setAgent(agent, true);
        guard.setMarketCap(RWA_MARKET, 400 ether);
        // Move to the middle of a period, so redemption is closed and the next window
        // is far away. That is the ordinary trading state.
        vm.warp(1_000_000 + 3 days);
        vault.touchOracle();
    }

    // ---- baseline: the ordinary path still works ----

    function test_freshOracleAndFarWindowAllowsExposure() public {
        (bool ok, string memory reason) = guard.rwaTradeable();
        assertTrue(ok, reason);
        vm.prank(agent);
        guard.addExposure(RWA_MARKET, 10 ether);
        assertEq(guard.exposureOf(RWA_MARKET), 10 ether);
    }

    // ---- refusal 1: stale oracle ----

    function test_staleOracleRefusesNewExposure() public {
        vm.warp(block.timestamp + MAX_ORACLE_AGE + 1);
        (bool ok, string memory reason) = guard.rwaTradeable();
        assertFalse(ok);
        assertEq(reason, "oracle mark is stale");

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                RwaRiskGuard.OracleStale.selector, MAX_ORACLE_AGE + 1, MAX_ORACLE_AGE
            )
        );
        guard.addExposure(RWA_MARKET, 1 ether);
    }

    /// A flat price and a stale price are NOT the same thing. touchOracle refreshes
    /// the timestamp without moving the price, and the guard must accept that.
    function test_aFlatOracleIsNotAStaleOracle() public {
        vm.warp(block.timestamp + MAX_ORACLE_AGE + 1);
        vault.touchOracle();
        (bool ok, ) = guard.rwaTradeable();
        assertTrue(ok, "a refreshed but unchanged mark must be tradeable");
        vm.prank(agent);
        guard.addExposure(RWA_MARKET, 1 ether);
    }

    // ---- refusal 2: issuer paused ----

    function test_issuerPauseRefusesNewExposure() public {
        vault.setPaused(true);
        (bool ok, string memory reason) = guard.rwaTradeable();
        assertFalse(ok);
        assertEq(reason, "issuer has paused the instrument");

        vm.prank(agent);
        vm.expectRevert(RwaRiskGuard.IssuerPaused.selector);
        guard.addExposure(RWA_MARKET, 1 ether);
    }

    // ---- refusal 3: redemption window proximity ----

    function test_exposureIsRefusedJustBeforeARedemptionWindow() public {
        // Warp to 6 hours before the next window opens, inside the 12 hour buffer.
        uint256 until = vault.secondsUntilWindow();
        vm.warp(block.timestamp + until - 6 hours);
        vault.touchOracle();

        uint256 remaining = vault.secondsUntilWindow();
        assertLe(remaining, WINDOW_BUFFER);
        assertGt(remaining, 0);

        (bool ok, string memory reason) = guard.rwaTradeable();
        assertFalse(ok);
        assertEq(reason, "redemption window opens too soon to take new exposure");

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                RwaRiskGuard.RedemptionWindowTooClose.selector, remaining, WINDOW_BUFFER
            )
        );
        guard.addExposure(RWA_MARKET, 1 ether);
    }

    function test_whileTheWindowIsOpenExposureIsAllowed() public {
        // Warp into an open window: untilWindow is 0, so the buffer does not apply.
        uint256 until = vault.secondsUntilWindow();
        vm.warp(block.timestamp + until + 1 hours);
        vault.touchOracle();
        assertTrue(vault.redemptionOpen());
        assertEq(vault.secondsUntilWindow(), 0);

        (bool ok, string memory reason) = guard.rwaTradeable();
        assertTrue(ok, reason);
    }

    // ---- refusal 4: oracle versus market divergence ----

    function test_divergenceBetweenOracleAndMarketRefusesNewExposure() public {
        // Oracle at 1.0, agent observes 1.05, which is 500 bps above a 300 bps limit.
        vm.prank(agent);
        guard.observeMarketPrice(1.05e18);
        assertEq(guard.divergenceBps(), 500);

        (bool ok, string memory reason) = guard.rwaTradeable();
        assertFalse(ok);
        assertEq(reason, "oracle and observed market price diverge");

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                RwaRiskGuard.OracleMarketDivergence.selector, 500, MAX_DIVERGENCE_BPS
            )
        );
        guard.addExposure(RWA_MARKET, 1 ether);
    }

    function test_divergenceWithinToleranceIsFine() public {
        vm.prank(agent);
        guard.observeMarketPrice(1.02e18); // 200 bps, under the 300 bps limit
        (bool ok, string memory reason) = guard.rwaTradeable();
        assertTrue(ok, reason);
        vm.prank(agent);
        guard.addExposure(RWA_MARKET, 1 ether);
    }

    function test_divergenceIsSymmetric() public {
        vm.prank(agent);
        guard.observeMarketPrice(0.95e18); // 500 bps below
        assertEq(guard.divergenceBps(), 500);
        (bool ok, ) = guard.rwaTradeable();
        assertFalse(ok, "downward divergence must refuse too");
    }

    // ---- THE ASYMMETRY: exits are never blocked ----

    function test_deriskingIsNeverBlockedByAnyRwaCondition() public {
        vm.prank(agent);
        guard.addExposure(RWA_MARKET, 100 ether);

        // Every refusal condition at once: paused, stale, divergent, near a window.
        vault.setPaused(true);
        vm.prank(agent);
        guard.observeMarketPrice(2e18); // 10000 bps divergence
        vm.warp(block.timestamp + 30 days);

        (bool ok, ) = guard.rwaTradeable();
        assertFalse(ok, "conditions should refuse new exposure");

        // And yet the exit must work. This is the whole point.
        vm.prank(agent);
        guard.reduceExposure(RWA_MARKET, 100 ether);
        assertEq(guard.exposureOf(RWA_MARKET), 0);
    }

    function test_deriskingWorksEvenWhenKilled() public {
        vm.prank(agent);
        guard.addExposure(RWA_MARKET, 50 ether);
        vm.prank(agent);
        guard.kill("rwa halt");
        vm.prank(agent);
        guard.reduceExposure(RWA_MARKET, 50 ether);
        assertEq(guard.exposureOf(RWA_MARKET), 0);
    }

    // ---- inherited guarantees must survive the subclass ----

    function test_inheritedCapsStillBind() public {
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                RiskGuard.MarketCapExceeded.selector, RWA_MARKET, 401 ether, 400 ether
            )
        );
        guard.addExposure(RWA_MARKET, 401 ether);
    }

    function test_inheritedKillSwitchStillBlocks() public {
        vm.prank(agent);
        guard.kill("halt");
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(RiskGuard.IsKilled.selector, "halt"));
        guard.addExposure(RWA_MARKET, 1 ether);
    }

    function test_agentStillCannotRevive() public {
        vm.prank(agent);
        guard.kill("halt");
        vm.prank(agent);
        vm.expectRevert(RiskGuard.NotOwner.selector);
        guard.revive();
    }

    function test_agentCannotLoosenTheRwaPolicy() public {
        vm.prank(agent);
        vm.expectRevert(RiskGuard.NotOwner.selector);
        guard.setRwaPolicy(type(uint256).max, 0, type(uint256).max);
        assertEq(guard.maxOracleAge(), MAX_ORACLE_AGE);
    }

    // ---- vault invariants ----

    /// Found by the mutation gate: removing the timestamp refresh from
    /// `setOraclePrice` stayed GREEN. That mutation matters, because a new mark that
    /// does not clear staleness would leave a freshly-updated instrument permanently
    /// untradeable, and the agent would refuse for a reason that is no longer true.
    function test_settingAPriceAlsoRefreshesItsTimestamp() public {
        vm.warp(block.timestamp + 5_000);
        assertEq(vault.oracleAge(), 5_000);

        vault.setOraclePrice(1.5e18);
        assertEq(vault.oracleAge(), 0, "a new mark must reset its own age");
        assertEq(vault.oraclePrice(), 1.5e18);

        // And the guard must agree that the instrument is tradeable again.
        (bool ok, ) = guard.rwaTradeable();
        assertTrue(ok, "fresh mark should restore tradeability");
    }

    function test_yieldIndexCannotDecrease() public {
        vault.accrueYield(1.05e18);
        assertEq(vault.yieldIndex(), 1.05e18);
        vm.expectRevert(
            abi.encodeWithSelector(RwaVault.YieldCannotDecrease.selector, 1.05e18, 1.01e18)
        );
        vault.accrueYield(1.01e18);
    }

    function test_onlyIssuerCanMoveTheOracle() public {
        vm.prank(agent);
        vm.expectRevert(RwaVault.NotIssuer.selector);
        vault.setOraclePrice(2e18);
    }

    /// Found by the mutation gate: removing `onlyIssuer` from `setPaused` stayed
    /// GREEN, which meant nothing tested it. An unguarded pause would let anyone halt
    /// the instrument, or unpause one the issuer had halted. Every issuer-only entry
    /// point is now covered.
    function test_onlyIssuerCanUseEveryIssuerOnlyEntryPoint() public {
        vm.startPrank(agent);

        vm.expectRevert(RwaVault.NotIssuer.selector);
        vault.setPaused(true);

        vm.expectRevert(RwaVault.NotIssuer.selector);
        vault.touchOracle();

        vm.expectRevert(RwaVault.NotIssuer.selector);
        vault.setWindowSchedule(1, 1);

        vm.expectRevert(RwaVault.NotIssuer.selector);
        vault.accrueYield(2e18);

        vm.expectRevert(RwaVault.NotIssuer.selector);
        vault.setOraclePrice(2e18);

        vm.stopPrank();

        // State unchanged by any of the refused attempts.
        assertFalse(vault.paused());
        assertEq(vault.yieldIndex(), 1e18);
        assertEq(vault.oraclePrice(), 1e18);
        assertEq(vault.windowPeriod(), WINDOW_PERIOD);
    }

    /// A stranger cannot report a market price, which would otherwise let anyone
    /// trip or clear the divergence refusal.
    function test_onlyAgentCanObserveMarketPrice() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(RiskGuard.NotAgent.selector);
        guard.observeMarketPrice(5e18);
        assertEq(guard.observedMarketPrice(), 0);
    }

    function test_oraclePriceCannotBeZero() public {
        vm.expectRevert(RwaVault.ZeroPrice.selector);
        vault.setOraclePrice(0);
    }

    /// The string-free view exists so the symbolic prover can reach these properties
    /// (halmos cannot execute MCOPY, which a `string memory` return emits). Two
    /// functions encoding the same decision is a duplication risk, so this pins them
    /// together across paused, stale, divergent, and window states.
    function testFuzz_theTwoTradeableViewsNeverDisagree(
        uint32 skip,
        bool paused,
        uint96 observed
    ) public {
        vault.setPaused(paused);
        if (observed > 0) {
            vm.prank(agent);
            guard.observeMarketPrice(uint256(observed));
        }
        vm.warp(block.timestamp + uint256(skip));

        (bool ok, ) = guard.rwaTradeable();
        assertEq(ok, guard.rwaTradeableFlag(), "tradeable views diverged");
    }

    function testFuzz_riskViewNeverDisagreesWithTheIndividualGetters(uint32 skip) public {
        vm.warp(block.timestamp + uint256(skip));
        (, uint256 age, bool paused, bool open, uint256 until, uint256 index) = vault.riskView();
        assertEq(age, vault.oracleAge());
        assertEq(paused, vault.paused());
        assertEq(open, vault.redemptionOpen());
        assertEq(until, vault.secondsUntilWindow());
        assertEq(index, vault.yieldIndex());
    }
}
