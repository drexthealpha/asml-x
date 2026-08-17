// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {OrderBookVenue} from "../src/OrderBookVenue.sol";
import {RiskGuard} from "../src/RiskGuard.sol";
import {BatchExecutor} from "../src/BatchExecutor.sol";
import {FeeCollector} from "../src/FeeCollector.sol";

/// Task 7.3. PASS: "every attempt to execute without the fee leg reverts, INCLUDING DIRECT VENUE
/// CALLS BY THE AGENT KEY."
///
/// THINKING: #22 inversion (do not ask whether the fee is charged on the happy path, ask what an
/// operator holding the agent key would do to avoid it), #29 pre-mortem, #66 adversarial.
///
/// The named fake win for this task is a test that only exercises the BatchExecutor, proving the
/// executor charges a fee while leaving the venue reachable behind its back. The counter, quoted from
/// TASKS.md: "the test must attempt the bypass directly against the venue and assert the revert."
/// So `agentKey` here is a real EOA holding real tokens with real approvals, and it tries every route
/// it actually has.
///
/// Two bypasses existed before this task and both are closed here:
///   A. `OrderBookVenue.take` was `external` with NO access control and the contract had no owner.
///      The agent key could fill any resting order directly. That skipped the fee AND the RiskGuard,
///      and the second half predates the fee entirely. The risk claim was procedural, not structural.
///   B. `BatchExecutor` enforced only that leg[0] was the RiskGuard. A batch with no fee leg was
///      well-formed.
contract FeeBypassTest is Test {
    MockERC20 base;
    MockERC20 quote;
    OrderBookVenue venue;
    RiskGuard guard;
    BatchExecutor exec;
    FeeCollector fee;

    address maker = address(0x1111);
    /// The operator's hot key. In production this is the key the agent signs with, so it is the
    /// realistic attacker: not an anonymous third party, the operator trying to keep its own fee.
    address agentKey = address(0xA6E7);
    address treasury = address(0x7777);
    bytes32 market;

    function setUp() public {
        base = new MockERC20("Test Base", "tBASE");
        quote = new MockERC20("Test Quote", "tQUOTE");
        venue = new OrderBookVenue();
        guard = new RiskGuard(1_000 ether);
        fee = new FeeCollector(treasury, 50);
        exec = new BatchExecutor(address(guard), address(fee));

        fee.setCharger(address(exec), true);
        venue.setAuthorisedTaker(address(exec), true);

        market = venue.marketId(address(base), address(quote));
        guard.setMarketCap(market, 500 ether);
        guard.setAgent(address(exec), true);

        base.mint(maker, 1_000 ether);
        vm.prank(maker);
        base.approve(address(venue), type(uint256).max);

        // The agent key is funded and fully approved everywhere. If it still cannot bypass the fee,
        // that is a structural result rather than an accident of a missing allowance.
        quote.mint(agentKey, 1_000 ether);
        vm.startPrank(agentKey);
        quote.approve(address(venue), type(uint256).max);
        quote.approve(address(fee), type(uint256).max);
        vm.stopPrank();

        quote.mint(address(exec), 1_000 ether);
        vm.startPrank(address(exec));
        quote.approve(address(venue), type(uint256).max);
        quote.approve(address(fee), type(uint256).max);
        vm.stopPrank();
    }

    function _postSell(uint256 size, uint256 price) internal returns (uint256 id) {
        vm.prank(maker);
        id = venue.postOrder(address(base), address(quote), false, size, price);
    }

    function _feeLeg(uint256 notional) internal view returns (BatchExecutor.Leg memory) {
        return BatchExecutor.Leg({
            target: address(fee),
            data: abi.encodeCall(FeeCollector.charge, (address(exec), market, address(quote), notional))
        });
    }

    // ---------------------------------------------------------------- bypass A: straight to the venue

    /// THE TEST THE TASK NAMES. The agent key holds tokens, holds approvals, and calls the venue
    /// directly. Before this task it worked and the fill landed with no fee and no exposure recorded.
    function test_agentKeyCannotFillDirectlyAtTheVenue() public {
        uint256 id = _postSell(10 ether, 2 ether);

        vm.expectRevert(
            abi.encodeWithSelector(OrderBookVenue.NotAuthorisedTaker.selector, agentKey)
        );
        vm.prank(agentKey);
        venue.take(id, 10 ether);

        // The revert is not the whole claim. Nothing moved, and the order is still fillable.
        assertEq(venue.remainingBase(id), 10 ether, "order untouched");
        assertEq(base.balanceOf(agentKey), 0, "agent received no base");
        assertEq(quote.balanceOf(maker), 0, "maker received no quote");
        assertEq(fee.chargeCount(), 0);
    }

    /// The bypass must stay closed for an arbitrary third party too, not only for the operator, or
    /// the venue is merely operator-restricted rather than executor-restricted.
    function test_anArbitraryAddressCannotFillDirectlyEither() public {
        uint256 id = _postSell(10 ether, 2 ether);
        address stranger = address(0xD00D);
        quote.mint(stranger, 100 ether);
        vm.prank(stranger);
        quote.approve(address(venue), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(OrderBookVenue.NotAuthorisedTaker.selector, stranger)
        );
        vm.prank(stranger);
        venue.take(id, 10 ether);
    }

    /// The negative control for the two tests above. If `take` reverted for EVERY caller the two
    /// bypass tests would pass while the venue was simply broken, and the suite would be green on a
    /// dead contract. This proves the authorised path still works, so the reverts above are about
    /// authorisation and not about a bricked function.
    function test_theAuthorisedExecutorCanStillFill() public {
        uint256 id = _postSell(10 ether, 2 ether);

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

        exec.execute(legs, bytes32(uint256(1)));

        assertEq(venue.remainingBase(id), 0, "the fill landed");
        assertEq(base.balanceOf(address(exec)), 10 ether);
        assertEq(fee.chargeCount(), 1, "and it paid the fee");
        assertEq(quote.balanceOf(treasury), fee.quoteFee(20 ether));
    }

    /// Authorisation is revocable, which is what makes it a control rather than a constructor
    /// argument. A compromised executor has to be stoppable without redeploying the venue and
    /// orphaning every resting order.
    function test_takerAuthorisationCanBeRevoked() public {
        uint256 id = _postSell(10 ether, 2 ether);
        venue.setAuthorisedTaker(address(exec), false);

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
        exec.execute(legs, bytes32(uint256(2)));
        assertEq(venue.remainingBase(id), 10 ether);
    }

    function test_onlyTheVenueOwnerCanAuthoriseATaker() public {
        vm.expectRevert(OrderBookVenue.NotVenueOwner.selector);
        vm.prank(agentKey);
        venue.setAuthorisedTaker(agentKey, true);
    }

    // ------------------------------------------------- bypass B: a batch built without the fee leg

    /// The operator controls the batch contents. Omitting the fee leg is the cheapest possible
    /// bypass and needs no exploit at all.
    function test_aBatchWithNoFeeLegReverts() public {
        uint256 id = _postSell(10 ether, 2 ether);

        BatchExecutor.Leg[] memory legs = new BatchExecutor.Leg[](2);
        legs[0] = BatchExecutor.Leg({
            target: address(guard),
            data: abi.encodeCall(RiskGuard.addExposure, (market, 20 ether))
        });
        legs[1] = BatchExecutor.Leg({
            target: address(venue),
            data: abi.encodeCall(OrderBookVenue.take, (id, 10 ether))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                BatchExecutor.LastLegMustBeFeeCollector.selector, address(venue), address(fee)
            )
        );
        exec.execute(legs, bytes32(uint256(3)));

        assertEq(venue.remainingBase(id), 10 ether, "no fill without a fee");
        assertEq(guard.exposureOf(market), 0, "and no exposure recorded");
    }

    /// The subtler version, and the one worth writing: put the fee leg in the batch but not LAST,
    /// with a venue fill after it. If the check were "contains a fee leg" rather than "ends with
    /// one", this would pass and the operator could charge a fee on a tiny notional and then fill a
    /// large one behind it.
    function test_aFeeLegThatIsNotLastReverts() public {
        uint256 id = _postSell(10 ether, 2 ether);

        BatchExecutor.Leg[] memory legs = new BatchExecutor.Leg[](3);
        legs[0] = BatchExecutor.Leg({
            target: address(guard),
            data: abi.encodeCall(RiskGuard.addExposure, (market, 20 ether))
        });
        legs[1] = _feeLeg(1);
        legs[2] = BatchExecutor.Leg({
            target: address(venue),
            data: abi.encodeCall(OrderBookVenue.take, (id, 10 ether))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                BatchExecutor.LastLegMustBeFeeCollector.selector, address(venue), address(fee)
            )
        );
        exec.execute(legs, bytes32(uint256(4)));
        assertEq(fee.chargeCount(), 0);
    }

    /// A fee leg pointed at an attacker-deployed collector. `feeCollector` is immutable, so the
    /// comparison is against an address no operator can move.
    function test_aBatchPointedAtAnImpostorCollectorReverts() public {
        FeeCollector impostor = new FeeCollector(agentKey, 0);
        uint256 id = _postSell(10 ether, 2 ether);

        BatchExecutor.Leg[] memory legs = new BatchExecutor.Leg[](3);
        legs[0] = BatchExecutor.Leg({
            target: address(guard),
            data: abi.encodeCall(RiskGuard.addExposure, (market, 20 ether))
        });
        legs[1] = BatchExecutor.Leg({
            target: address(venue),
            data: abi.encodeCall(OrderBookVenue.take, (id, 10 ether))
        });
        legs[2] = BatchExecutor.Leg({
            target: address(impostor),
            data: abi.encodeCall(
                FeeCollector.charge, (address(exec), market, address(quote), 20 ether)
            )
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                BatchExecutor.LastLegMustBeFeeCollector.selector, address(impostor), address(fee)
            )
        );
        exec.execute(legs, bytes32(uint256(5)));
    }

    /// The fee leg reverting must take the whole batch with it, so an operator cannot arrange for a
    /// failing fee and keep the fill. Approval is revoked, which is the realistic way to make it fail
    /// without touching the fee contract.
    function test_aFailingFeeLegRevertsTheFillToo() public {
        uint256 id = _postSell(10 ether, 2 ether);
        vm.prank(address(exec));
        quote.approve(address(fee), 0);

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
        exec.execute(legs, bytes32(uint256(6)));

        assertEq(venue.remainingBase(id), 10 ether, "the fill was undone with the fee");
        assertEq(guard.exposureOf(market), 0);
        assertEq(quote.balanceOf(treasury), 0);
    }

    /// `approveToken` exists because a deployed contract cannot `vm.prank` itself into granting an
    /// allowance. It is owner-gated, and this checks both halves: the owner can grant, and the agent
    /// key cannot. Without the second half it would be a new bypass rather than a fix, since an
    /// allowance granted to an attacker-chosen spender drains the executor's quote balance.
    function test_approveTokenIsOwnerGatedAndActuallyGrants() public {
        exec.approveToken(address(quote), address(0xF00D), 123 ether);
        assertEq(quote.allowance(address(exec), address(0xF00D)), 123 ether);

        vm.expectRevert(BatchExecutor.NotOwner.selector);
        vm.prank(agentKey);
        exec.approveToken(address(quote), agentKey, type(uint256).max);
        assertEq(quote.allowance(address(exec), agentKey), 0);
    }

    /// Every route the agent key actually has, in one place, so the claim "there is no fee-free path"
    /// is a claim about an enumerated set rather than about the two routes I happened to think of
    /// while writing the fix.
    function test_enumerateEveryRouteTheAgentKeyHas() public {
        uint256 id = _postSell(10 ether, 2 ether);

        // 1. Direct venue call.
        vm.expectRevert();
        vm.prank(agentKey);
        venue.take(id, 10 ether);

        // 2. Direct call to the fee collector, to pre-pay a token fee and claim it covered a fill.
        //    Blocked because only the executor is a charger, so no self-issued fee event exists.
        vm.expectRevert(FeeCollector.NotCharger.selector);
        vm.prank(agentKey);
        fee.charge(agentKey, market, address(quote), 1);

        // 3. Driving the executor at all. It is onlyOwner, and the agent key is not the deployer.
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
        vm.prank(agentKey);
        exec.execute(legs, bytes32(uint256(7)));

        // 4. Authorising itself at the venue. Owner-gated.
        vm.expectRevert(OrderBookVenue.NotVenueOwner.selector);
        vm.prank(agentKey);
        venue.setAuthorisedTaker(agentKey, true);

        // 5. Making itself a charger. Owner-gated.
        vm.expectRevert(FeeCollector.NotOwner.selector);
        vm.prank(agentKey);
        fee.setCharger(agentKey, true);

        // Nothing at all moved across all five routes.
        assertEq(venue.remainingBase(id), 10 ether);
        assertEq(fee.chargeCount(), 0);
        assertEq(base.balanceOf(agentKey), 0);
    }
}
