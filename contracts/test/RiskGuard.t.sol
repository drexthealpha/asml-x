// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {RiskGuard} from "../src/RiskGuard.sol";

contract RiskGuardTest is Test {
    RiskGuard guard;
    address owner = address(this);
    address agent = address(0xA6E17);
    address stranger = address(0x5747);

    bytes32 constant M1 = keccak256("M1");
    bytes32 constant M2 = keccak256("M2");

    function setUp() public {
        guard = new RiskGuard(1_000 ether);
        guard.setAgent(agent, true);
        guard.setMarketCap(M1, 400 ether);
        guard.setMarketCap(M2, 400 ether);
    }

    // ---- invariant 1: per-market cap ----

    function test_addExposure_respectsMarketCap() public {
        vm.prank(agent);
        guard.addExposure(M1, 400 ether);
        assertEq(guard.exposureOf(M1), 400 ether);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(RiskGuard.MarketCapExceeded.selector, M1, 400 ether + 1, 400 ether)
        );
        guard.addExposure(M1, 1);
    }

    // ---- invariant 2: gross cap ----

    function test_addExposure_respectsGrossCap() public {
        guard.setMarketCap(M1, 900 ether);
        guard.setMarketCap(M2, 900 ether);
        vm.prank(agent);
        guard.addExposure(M1, 600 ether);
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(RiskGuard.GrossCapExceeded.selector, 1_001 ether, 1_000 ether)
        );
        guard.addExposure(M2, 401 ether);
    }

    // ---- an unconfigured market fails closed ----

    function test_unknownMarketIsRefused() public {
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(RiskGuard.MarketNotConfigured.selector, keccak256("NOPE"))
        );
        guard.addExposure(keccak256("NOPE"), 1);
    }

    // ---- invariant 3: killed blocks everything that adds risk ----

    function test_killedBlocksAddExposure() public {
        vm.prank(agent);
        guard.kill("daily loss breached");
        assertTrue(guard.killed());

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(RiskGuard.IsKilled.selector, "daily loss breached")
        );
        guard.addExposure(M1, 1);
    }

    /// De-risking must never be blocked by a halt. A kill switch that traps the
    /// agent in its position is a worse outcome than the risk it was stopping.
    function test_killedStillAllowsReduce() public {
        vm.prank(agent);
        guard.addExposure(M1, 100 ether);
        vm.prank(agent);
        guard.kill("halt");
        vm.prank(agent);
        guard.reduceExposure(M1, 100 ether);
        assertEq(guard.exposureOf(M1), 0);
        assertEq(guard.gross(), 0);
    }

    // ---- invariant 4: the agent can halt but never un-halt ----

    function test_agentCannotRevive() public {
        vm.prank(agent);
        guard.kill("halt");
        vm.prank(agent);
        vm.expectRevert(RiskGuard.NotOwner.selector);
        guard.revive();
        assertTrue(guard.killed());
    }

    function test_ownerCanRevive() public {
        vm.prank(agent);
        guard.kill("halt");
        guard.revive();
        assertFalse(guard.killed());
    }

    function test_agentCannotRaiseCaps() public {
        vm.prank(agent);
        vm.expectRevert(RiskGuard.NotOwner.selector);
        guard.setMaxGross(type(uint256).max);

        vm.prank(agent);
        vm.expectRevert(RiskGuard.NotOwner.selector);
        guard.setMarketCap(M1, type(uint256).max);
    }

    function test_strangerCannotDoAnything() public {
        vm.prank(stranger);
        vm.expectRevert(RiskGuard.NotAgent.selector);
        guard.addExposure(M1, 1);

        vm.prank(stranger);
        vm.expectRevert(RiskGuard.NotAgent.selector);
        guard.kill("nope");

        vm.prank(stranger);
        vm.expectRevert(RiskGuard.NotOwner.selector);
        guard.revive();
    }

    // ---- reduce cannot underflow into free headroom ----

    function test_reduceCannotExceedExposure() public {
        vm.prank(agent);
        guard.addExposure(M1, 10 ether);
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                RiskGuard.ReduceExceedsExposure.selector, M1, 11 ether, 10 ether
            )
        );
        guard.reduceExposure(M1, 11 ether);
    }

    // ---- headroom is never a lie ----

    function testFuzz_headroomIsHonest(uint96 a, uint96 b) public {
        uint256 amtA = uint256(a) % 400 ether;
        uint256 amtB = uint256(b) % 400 ether;
        vm.assume(amtA > 0 && amtB > 0);

        uint256 room = guard.headroom(M1);
        vm.prank(agent);
        if (amtA <= room) {
            guard.addExposure(M1, amtA);
        }
        uint256 room2 = guard.headroom(M2);
        if (amtB <= room2) {
            vm.prank(agent);
            guard.addExposure(M2, amtB);
        }
        // Whatever happened, no cap is broken and the aggregate matches parts.
        assertLe(guard.exposureOf(M1), guard.maxPerMarket(M1));
        assertLe(guard.exposureOf(M2), guard.maxPerMarket(M2));
        assertLe(guard.gross(), guard.maxGross());
        assertEq(guard.gross(), guard.sumOfParts());
    }
}

/// @dev Handler for stateful invariant testing. Only the agent role, only valid
///      calls, so the fuzzer explores real sequences rather than reverts.
contract GuardHandler {
    RiskGuard public guard;
    bytes32[] public marketList;

    constructor(RiskGuard _guard, bytes32 m1, bytes32 m2) {
        guard = _guard;
        marketList.push(m1);
        marketList.push(m2);
    }

    function add(uint256 which, uint256 amount) external {
        bytes32 m = marketList[which % marketList.length];
        amount = amount % 500 ether;
        if (amount == 0) return;
        try guard.addExposure(m, amount) {} catch {}
    }

    function reduce(uint256 which, uint256 amount) external {
        bytes32 m = marketList[which % marketList.length];
        amount = amount % 500 ether;
        if (amount == 0) return;
        try guard.reduceExposure(m, amount) {} catch {}
    }

    /// @dev Gated deliberately. An ungated kill was called in roughly a third of
    ///      fuzz calls, after which every `add` reverted and the cap invariants
    ///      passed vacuously: they were verifying a halted contract that could not
    ///      break a cap even in principle. The gate keeps the killed state
    ///      reachable while leaving the exposure paths as the main thing explored.
    ///      The killed behaviour itself has dedicated non-vacuous unit tests.
    function killIt(uint256 seed) external {
        if (seed % 97 != 0) return;
        try guard.kill("fuzz") {} catch {}
    }

    /// @dev Counts successful adds so an invariant can assert the fuzzer actually
    ///      exercised the path rather than reverting through the whole run.
    uint256 public successfulAdds;

    function addCounted(uint256 which, uint256 amount) external {
        bytes32 m = marketList[which % marketList.length];
        amount = amount % 200 ether;
        if (amount == 0) return;
        try guard.addExposure(m, amount) {
            successfulAdds += 1;
        } catch {}
    }
}

contract RiskGuardInvariantTest is StdInvariant, Test {
    RiskGuard guard;
    GuardHandler handler;

    bytes32 constant M1 = keccak256("M1");
    bytes32 constant M2 = keccak256("M2");

    function setUp() public {
        guard = new RiskGuard(1_000 ether);
        guard.setMarketCap(M1, 400 ether);
        guard.setMarketCap(M2, 400 ether);
        handler = new GuardHandler(guard, M1, M2);
        guard.setAgent(address(handler), true);
        targetContract(address(handler));

        // Restrict the campaign to the exposure paths. With `killIt` in the mix,
        // a sequence could halt the guard on its first call, after which every
        // add reverts and the cap invariants hold vacuously against a contract
        // that cannot break a cap even in principle. The killed state has its own
        // non-vacuous unit tests in RiskGuardTest, which is the right place for a
        // property about a specific state rather than about reachable sequences.
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = GuardHandler.addCounted.selector;
        selectors[1] = GuardHandler.reduce.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// Reachability, checked once and cheaply. If the handler cannot add exposure
    /// at all then the invariant campaign below is exploring nothing, and this
    /// test says so directly rather than leaving it to be inferred.
    function test_handlerCanReachARiskyState() public {
        handler.addCounted(0, 100 ether);
        assertGt(handler.successfulAdds(), 0);
        assertGt(guard.gross(), 0);
    }

    /// Invariant 5: the O(1) aggregate always equals the O(n) recomputation.
    /// If these ever diverge, the incremental accounting is broken and every cap
    /// check downstream is meaningless.
    function invariant_grossEqualsSumOfParts() public view {
        assertEq(guard.gross(), guard.sumOfParts());
    }

    /// Invariants 1 and 2: no reachable state breaks a cap.
    function invariant_capsAreNeverExceeded() public view {
        assertLe(guard.exposureOf(M1), guard.maxPerMarket(M1));
        assertLe(guard.exposureOf(M2), guard.maxPerMarket(M2));
        assertLe(guard.gross(), guard.maxGross());
    }

    /// Once killed, exposure can never rise. Reachable here only via a direct
    /// kill in a unit test, which is why the killed-state properties live in
    /// RiskGuardTest and this campaign focuses on the exposure arithmetic.
    function invariant_grossNeverExceedsCapEvenAfterReduces() public view {
        assertLe(guard.gross(), guard.maxGross());
    }
}
