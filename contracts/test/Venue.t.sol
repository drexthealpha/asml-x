// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {OrderBookVenue} from "../src/OrderBookVenue.sol";
import {RiskGuard} from "../src/RiskGuard.sol";
import {BatchExecutor} from "../src/BatchExecutor.sol";
import {FeeCollector} from "../src/FeeCollector.sol";

contract VenueTest is Test {
    MockERC20 base;
    MockERC20 quote;
    OrderBookVenue venue;

    address maker = address(0x1111);
    address taker = address(0x2222);

    function setUp() public {
        base = new MockERC20("Test Base", "tBASE");
        quote = new MockERC20("Test Quote", "tQUOTE");
        venue = new OrderBookVenue();

        // This suite tests the venue's own escrow and fill arithmetic in isolation, so `taker` stands
        // in for the executor. Authorised explicitly rather than left open, because leaving `take`
        // callable by anyone is exactly the bypass task 7.3 closed.
        venue.setAuthorisedTaker(taker, true);

        base.mint(maker, 1_000 ether);
        quote.mint(maker, 1_000 ether);
        base.mint(taker, 1_000 ether);
        quote.mint(taker, 1_000 ether);

        vm.prank(maker);
        base.approve(address(venue), type(uint256).max);
        vm.prank(maker);
        quote.approve(address(venue), type(uint256).max);
        vm.prank(taker);
        base.approve(address(venue), type(uint256).max);
        vm.prank(taker);
        quote.approve(address(venue), type(uint256).max);
    }

    /// The escrow claim: posting a sell actually moves the maker's base into the
    /// contract. If it did not, a "fill" later would be fiction.
    function test_postingASellEscrowsTheBase() public {
        uint256 before = base.balanceOf(maker);
        vm.prank(maker);
        venue.postOrder(address(base), address(quote), false, 10 ether, 2 ether);
        assertEq(base.balanceOf(maker), before - 10 ether);
        assertEq(base.balanceOf(address(venue)), 10 ether);
    }

    function test_postingABuyEscrowsTheQuote() public {
        uint256 before = quote.balanceOf(maker);
        vm.prank(maker);
        venue.postOrder(address(base), address(quote), true, 10 ether, 2 ether);
        // 10 base at 2 quote each = 20 quote escrowed.
        assertEq(quote.balanceOf(maker), before - 20 ether);
        assertEq(quote.balanceOf(address(venue)), 20 ether);
    }

    function test_takeMovesBothAssetsAndClearsEscrow() public {
        vm.prank(maker);
        uint256 id = venue.postOrder(address(base), address(quote), false, 10 ether, 2 ether);

        uint256 takerBaseBefore = base.balanceOf(taker);
        uint256 makerQuoteBefore = quote.balanceOf(maker);

        vm.prank(taker);
        uint256 paid = venue.take(id, 4 ether);

        assertEq(paid, 8 ether);
        assertEq(base.balanceOf(taker), takerBaseBefore + 4 ether);
        assertEq(quote.balanceOf(maker), makerQuoteBefore + 8 ether);
        assertEq(venue.remainingBase(id), 6 ether);
        assertEq(base.balanceOf(address(venue)), 6 ether);
    }

    function test_partialFillsAccumulateExactly() public {
        vm.prank(maker);
        uint256 id = venue.postOrder(address(base), address(quote), false, 9 ether, 3 ether);
        vm.prank(taker);
        venue.take(id, 3 ether);
        vm.prank(taker);
        venue.take(id, 3 ether);
        assertEq(venue.remainingBase(id), 3 ether);
        vm.prank(taker);
        venue.take(id, 3 ether);
        assertEq(venue.remainingBase(id), 0);

        vm.prank(taker);
        vm.expectRevert(OrderBookVenue.NothingToFill.selector);
        venue.take(id, 1);
    }

    function test_cannotOverfill() public {
        vm.prank(maker);
        uint256 id = venue.postOrder(address(base), address(quote), false, 5 ether, 1 ether);
        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrderBookVenue.FillExceedsRemaining.selector, 6 ether, 5 ether
            )
        );
        venue.take(id, 6 ether);
    }

    function test_cancelRefundsTheUnfilledRemainder() public {
        vm.prank(maker);
        uint256 id = venue.postOrder(address(base), address(quote), false, 10 ether, 2 ether);
        vm.prank(taker);
        venue.take(id, 4 ether);

        uint256 makerBaseBefore = base.balanceOf(maker);
        vm.prank(maker);
        venue.cancel(id);
        assertEq(base.balanceOf(maker), makerBaseBefore + 6 ether);
        assertEq(base.balanceOf(address(venue)), 0);
    }

    function test_onlyMakerCanCancel() public {
        vm.prank(maker);
        uint256 id = venue.postOrder(address(base), address(quote), false, 10 ether, 2 ether);
        vm.prank(taker);
        vm.expectRevert(OrderBookVenue.NotMaker.selector);
        venue.cancel(id);
    }

    /// Solvency: the venue must always hold at least what it owes to open orders.
    /// Fuzzed over fill sizes because this is where a rounding error would hide.
    function testFuzz_venueRemainsSolventAcrossPartialFills(uint96 raw) public {
        uint256 fill = (uint256(raw) % 10 ether) + 1;
        vm.prank(maker);
        uint256 id = venue.postOrder(address(base), address(quote), false, 10 ether, 2 ether);
        if (fill > 10 ether) fill = 10 ether;
        vm.prank(taker);
        venue.take(id, fill);
        assertEq(base.balanceOf(address(venue)), venue.remainingBase(id));
    }
}

contract BatchExecutorTest is Test {
    MockERC20 base;
    MockERC20 quote;
    OrderBookVenue venue;
    RiskGuard guard;
    BatchExecutor exec;
    FeeCollector feeCollector;
    address treasury = address(0x7777);

    address maker = address(0x1111);
    bytes32 market;

    function setUp() public {
        base = new MockERC20("Test Base", "tBASE");
        quote = new MockERC20("Test Quote", "tQUOTE");
        venue = new OrderBookVenue();
        guard = new RiskGuard(1_000 ether);
        feeCollector = new FeeCollector(treasury, 50);
        exec = new BatchExecutor(address(guard), address(feeCollector));
        feeCollector.setCharger(address(exec), true);
        venue.setAuthorisedTaker(address(exec), true);

        market = venue.marketId(address(base), address(quote));
        guard.setMarketCap(market, 50 ether);
        guard.setAgent(address(exec), true);

        base.mint(maker, 1_000 ether);
        quote.mint(address(exec), 1_000 ether);

        vm.prank(maker);
        base.approve(address(venue), type(uint256).max);

        // The executor pays its own usage fee out of the quote it holds.
        vm.prank(address(exec));
        quote.approve(address(feeCollector), type(uint256).max);
    }

    /// The fee leg every batch must end with. A helper rather than four copies, because the batches
    /// below are testing the guard and the venue, not the fee, and an inlined encodeCall in each one
    /// would be four places to get the argument order wrong.
    function _feeLeg(uint256 notional) internal view returns (BatchExecutor.Leg memory) {
        return BatchExecutor.Leg({
            target: address(feeCollector),
            data: abi.encodeCall(
                FeeCollector.charge, (address(exec), market, address(quote), notional)
            )
        });
    }

    function _postSell(uint256 size, uint256 price) internal returns (uint256 id) {
        vm.prank(maker);
        id = venue.postOrder(address(base), address(quote), false, size, price);
    }

    function test_batchRequiresTheGuardAsItsFirstLeg() public {
        BatchExecutor.Leg[] memory legs = new BatchExecutor.Leg[](1);
        legs[0] = BatchExecutor.Leg({
            target: address(venue),
            data: abi.encodeCall(OrderBookVenue.cancel, (0))
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                BatchExecutor.FirstLegMustBeRiskGuard.selector, address(venue), address(guard)
            )
        );
        exec.execute(legs, bytes32(uint256(1)));
    }

    /// The atomicity claim. A cap breach in leg 1 must prevent leg 2 from moving
    /// any tokens at all. This is the property that makes mid-sequence failure
    /// safe rather than something the risk engine has to unwind.
    function test_capBreachInLegOneRevertsTheWholeBatchAndMovesNothing() public {
        uint256 id = _postSell(40 ether, 2 ether);

        // 40 base at 2 quote = 80 quote exposure, above the 50 ether market cap.
        BatchExecutor.Leg[] memory legs = new BatchExecutor.Leg[](3);
        legs[0] = BatchExecutor.Leg({
            target: address(guard),
            data: abi.encodeCall(RiskGuard.addExposure, (market, 80 ether))
        });
        legs[1] = BatchExecutor.Leg({
            target: address(venue),
            data: abi.encodeCall(OrderBookVenue.take, (id, 40 ether))
        });
        legs[2] = _feeLeg(80 ether);

        uint256 venueBaseBefore = base.balanceOf(address(venue));
        uint256 execQuoteBefore = quote.balanceOf(address(exec));

        vm.expectRevert();
        exec.execute(legs, bytes32(uint256(7)));

        // Nothing moved. Not "less moved", nothing.
        assertEq(base.balanceOf(address(venue)), venueBaseBefore);
        assertEq(quote.balanceOf(address(exec)), execQuoteBefore);
        assertEq(guard.exposureOf(market), 0);
        assertEq(venue.remainingBase(id), 40 ether);
    }

    function test_withinCapTheWholeBatchLands() public {
        uint256 id = _postSell(20 ether, 2 ether);

        BatchExecutor.Leg[] memory legs = new BatchExecutor.Leg[](3);
        legs[0] = BatchExecutor.Leg({
            target: address(guard),
            data: abi.encodeCall(RiskGuard.addExposure, (market, 40 ether))
        });
        legs[1] = BatchExecutor.Leg({
            target: address(venue),
            data: abi.encodeCall(OrderBookVenue.take, (id, 20 ether))
        });
        legs[2] = _feeLeg(40 ether);

        vm.prank(address(exec));
        quote.approve(address(venue), type(uint256).max);

        exec.execute(legs, bytes32(uint256(8)));

        assertEq(guard.exposureOf(market), 40 ether);
        assertEq(base.balanceOf(address(exec)), 20 ether);
        assertEq(venue.remainingBase(id), 0);
    }

    /// A killed guard stops the batch before any token moves.
    function test_killedGuardStopsTheBatch() public {
        uint256 id = _postSell(10 ether, 2 ether);
        guard.kill("operator halt");

        BatchExecutor.Leg[] memory legs = new BatchExecutor.Leg[](3);
        legs[0] = BatchExecutor.Leg({
            target: address(guard),
            data: abi.encodeCall(RiskGuard.addExposure, (market, 20 ether))
        });
        legs[1] = BatchExecutor.Leg({
            target: address(venue),
            data: abi.encodeCall(OrderBookVenue.take, (id, 10 ether))
        });
        legs[2] = _feeLeg(20 ether);

        vm.expectRevert();
        exec.execute(legs, bytes32(uint256(9)));
        assertEq(venue.remainingBase(id), 10 ether);
    }
}
