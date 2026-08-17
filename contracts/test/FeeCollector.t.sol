// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {FeeCollector} from "../src/FeeCollector.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// Task 7.2. The PASS condition is that the fee is charged on every approved execution and the event
/// carries the numbers a dashboard needs.
///
/// The named fake win for 7.2 is an event emitted with values the TEST computed rather than the
/// CONTRACT. So the expectations here are written against `quoteFee`, which is the contract's own
/// arithmetic, and 7.4 proves symbolically that `quoteFee` equals `notional * bps / 10000` for every
/// input in range. The test and the proof check different things on purpose.
contract FeeCollectorTest is Test {
    FeeCollector fee;
    MockERC20 token;
    address treasury = address(0xBEEF);
    address payer = address(0xCAFE);
    address executor = address(0xEEEE);
    bytes32 constant MARKET = keccak256("tBASE/tQUOTE");

    event FeeCharged(
        address indexed payer,
        bytes32 indexed market,
        address token,
        uint256 notional,
        uint256 feeAmount,
        uint256 feeBps
    );

    function setUp() public {
        token = new MockERC20("Test Quote", "tQUOTE");
        fee = new FeeCollector(treasury, 50); // 0.5 percent
        fee.setCharger(executor, true);
        token.mint(payer, 1_000_000 ether);
        vm.prank(payer);
        token.approve(address(fee), type(uint256).max);
    }

    function test_chargeMovesTokensAndEmitsTheNumbers() public {
        uint256 notional = 1_000 ether;
        uint256 expected = fee.quoteFee(notional);
        assertGt(expected, 0, "a 1000 unit notional at 50 bps must not round to zero");

        vm.expectEmit(true, true, true, true);
        emit FeeCharged(payer, MARKET, address(token), notional, expected, 50);

        vm.prank(executor);
        uint256 charged = fee.charge(payer, MARKET, address(token), notional);

        assertEq(charged, expected);
        assertEq(token.balanceOf(treasury), expected, "treasury received exactly the fee");
        assertEq(fee.totalCollected(address(token)), expected);
        assertEq(fee.chargeCount(), 1);
    }

    /// The ceiling is the whole safety story for this contract, so it is tested from both directions.
    function test_feeCanOnlyBeLoweredNeverRaised() public {
        assertEq(fee.feeBps(), 50);

        fee.setFeeBps(25);
        assertEq(fee.feeBps(), 25, "lowering is allowed");

        vm.expectRevert(abi.encodeWithSelector(FeeCollector.FeeNotLowered.selector, 25, 40));
        fee.setFeeBps(40);

        vm.expectRevert(abi.encodeWithSelector(FeeCollector.FeeNotLowered.selector, 25, 25));
        fee.setFeeBps(25);
    }

    function test_constructorRefusesAFeeAboveTheCeiling() public {
        uint256 ceiling = fee.MAX_FEE_BPS();
        vm.expectRevert(
            abi.encodeWithSelector(FeeCollector.FeeAboveCeiling.selector, ceiling + 1, ceiling)
        );
        new FeeCollector(treasury, ceiling + 1);
    }

    /// An arbitrary caller emitting fee events would inflate the growth counter task 13.1 publishes.
    function test_onlyAnApprovedChargerCanCharge() public {
        vm.expectRevert(FeeCollector.NotCharger.selector);
        vm.prank(address(0xD00D));
        fee.charge(payer, MARKET, address(token), 1_000 ether);
    }

    function test_onlyOwnerCanChangeAnything() public {
        vm.startPrank(address(0xD00D));
        vm.expectRevert(FeeCollector.NotOwner.selector);
        fee.setFeeBps(10);
        vm.expectRevert(FeeCollector.NotOwner.selector);
        fee.setCharger(address(0x1), true);
        vm.expectRevert(FeeCollector.NotOwner.selector);
        fee.setTreasury(address(0x1));
        vm.stopPrank();
    }

    /// A notional small enough to round the fee to zero must charge nothing AND emit nothing.
    /// Emitting a zero-value event would inflate the event count that the growth surface reports.
    function test_dustNotionalChargesNothingAndEmitsNothing() public {
        uint256 dust = 199; // 199 * 50 / 10000 = 0 by integer division
        assertEq(fee.quoteFee(dust), 0);

        vm.recordLogs();
        vm.prank(executor);
        uint256 charged = fee.charge(payer, MARKET, address(token), dust);

        assertEq(charged, 0);
        assertEq(vm.getRecordedLogs().length, 0, "no event for a zero fee");
        assertEq(fee.chargeCount(), 0, "a zero fee is not a charge");
    }

    /// Task 7.1's headline lesson, from Code4rena Cudos 2022 issue 3: trusting the amount argument
    /// instead of the observed balance delta mis-accounts every fee-on-transfer token.
    function test_aTokenThatUnderDeliversRevertsRatherThanUnderCollecting() public {
        SkimmingToken skimmer = new SkimmingToken();
        skimmer.mint(payer, 1_000_000 ether);
        vm.prank(payer);
        skimmer.approve(address(fee), type(uint256).max);

        uint256 notional = 1_000 ether;
        uint256 expected = fee.quoteFee(notional);

        vm.prank(executor);
        vm.expectRevert();
        fee.charge(payer, MARKET, address(skimmer), notional);

        assertEq(skimmer.balanceOf(treasury), 0, "no partial collection was kept");
        assertGt(expected, 0);
    }

    /// Proportionality across magnitudes, so a single hand-picked example cannot hide a broken divisor.
    function testFuzz_feeIsAlwaysTheStatedFractionAndNeverExceedsTheCeiling(uint128 notional) public {
        uint256 n = uint256(notional);
        uint256 f = fee.quoteFee(n);
        assertLe(f * fee.BPS_DENOMINATOR(), n * fee.MAX_FEE_BPS(), "fee never exceeds the ceiling");
        assertEq(f, (n * fee.feeBps()) / fee.BPS_DENOMINATOR());
    }
}

/// A token that delivers less than it was asked to transfer. This is the fee-on-transfer failure the
/// research task identified, reproduced rather than described.
contract SkimmingToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        // Keeps 10 percent, reports success. Exactly the behaviour that breaks naive accounting.
        uint256 delivered = (amount * 90) / 100;
        balanceOf[from] -= amount;
        balanceOf[to] += delivered;
        return true;
    }
}
