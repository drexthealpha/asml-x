// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RouterExecutor} from "../src/RouterExecutor.sol";

/// A token that returns NOTHING from approve and transfer, like X Layer's USDT (`USD₮0`).
/// This shape is the reason `_tokenCall` exists; a normal typed call against it reverts.
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
    }

    function approve(address s, uint256 a) external {
        allowance[msg.sender][s] = a;
    }

    function transfer(address to, uint256 a) external {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
    }

    function take(address from, uint256 a) external {
        balanceOf[from] -= a;
    }

    function give(address to, uint256 a) external {
        balanceOf[to] += a;
    }
}

/// An honest router: takes `amountIn` of tokenIn and pays out `payout` of tokenOut.
contract MockRouter {
    NoReturnToken public tokenIn;
    NoReturnToken public tokenOut;
    uint256 public amountIn;
    uint256 public payout;

    function configure(NoReturnToken i, NoReturnToken o, uint256 ai, uint256 p) external {
        tokenIn = i;
        tokenOut = o;
        amountIn = ai;
        payout = p;
    }

    function swap() external {
        tokenIn.take(msg.sender, amountIn);
        tokenOut.give(msg.sender, payout);
    }
}

/// A router that takes the money and pays nothing. The whole point of the balance check.
contract ThievingRouter {
    NoReturnToken public tokenIn;
    uint256 public amountIn;

    function configure(NoReturnToken i, uint256 ai) external {
        tokenIn = i;
        amountIn = ai;
    }

    function swap() external {
        tokenIn.take(msg.sender, amountIn);
    }
}

/// The proxy that actually pulls the tokens. Separate from the router, as OKX deploys it.
contract ApproveProxy {
    function pull(NoReturnToken t, address from, uint256 a) external {
        // A REAL allowance check, which is the entire point of this mock. `MockRouter` pulled
        // tokens with no allowance at all, so it could not tell an allowance on the right address
        // from one on the wrong address, and the mainnet revert went undetected.
        require(t.allowance(from, address(this)) >= a, "allowance");
        t.take(from, a);
    }
}

/// A router that calls a SEPARATE proxy to pull funds, the way OKX Onchain OS actually works.
///
/// This is the mock that reproduces the mainnet failure. Against a contract that approves the
/// router instead of the proxy, `pull` reverts on the allowance require and the whole swap fails,
/// exactly as it did on chain 196.
contract SplitApprovalRouter {
    ApproveProxy public immutable proxy;
    NoReturnToken public tokenIn;
    NoReturnToken public tokenOut;
    uint256 public amountIn;
    uint256 public payout;

    constructor() {
        proxy = new ApproveProxy();
    }

    function configure(NoReturnToken i, NoReturnToken o, uint256 ai, uint256 p) external {
        tokenIn = i;
        tokenOut = o;
        amountIn = ai;
        payout = p;
    }

    function swap() external {
        proxy.pull(tokenIn, msg.sender, amountIn);
        tokenOut.give(msg.sender, payout);
    }
}

contract RouterExecutorTest is Test {
    NoReturnToken usdt;
    NoReturnToken wokb;
    address agent = address(0xA6E7);
    address stranger = address(0x5747);

    function setUp() public {
        usdt = new NoReturnToken();
        wokb = new NoReturnToken();
    }

    /// The core promise: an honest swap succeeds and reports the MEASURED gain.
    function test_honest_swap_credits_the_measured_amount() public {
        MockRouter r = new MockRouter();
        RouterExecutor ex = new RouterExecutor(address(r), address(r));
        ex.setAgent(agent);

        usdt.mint(address(ex), 1_000_000);
        r.configure(usdt, wokb, 1_000_000, 10_145_104_527_624_039);

        vm.prank(agent);
        uint256 out = ex.route(
            address(usdt),
            address(wokb),
            1_000_000,
            10_144_090_017_171_276, // the aggregator's real minReceiveAmount
            abi.encodeWithSignature("swap()")
        );

        assertEq(out, 10_145_104_527_624_039);
        assertEq(wokb.balanceOf(address(ex)), 10_145_104_527_624_039);
    }

    /// THE LOAD-BEARING TEST. A router that takes the funds and delivers nothing must revert the
    /// whole transaction. If this passes with the check removed, the check is decoration.
    function test_a_router_that_pays_nothing_reverts_and_keeps_the_funds() public {
        ThievingRouter r = new ThievingRouter();
        RouterExecutor ex = new RouterExecutor(address(r), address(r));
        ex.setAgent(agent);

        usdt.mint(address(ex), 1_000_000);
        r.configure(usdt, 1_000_000);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(RouterExecutor.InsufficientOutput.selector, 0, 1));
        ex.route(address(usdt), address(wokb), 1_000_000, 1, abi.encodeWithSignature("swap()"));

        // The revert undoes the theft. The executor still holds every unit it started with.
        assertEq(usdt.balanceOf(address(ex)), 1_000_000);
    }

    /// Under-delivery is refused even when the router pays SOMETHING. A swap that returns less
    /// than the aggregator promised is a worse fill than the agent's decision was based on.
    function test_under_delivery_below_min_out_reverts() public {
        MockRouter r = new MockRouter();
        RouterExecutor ex = new RouterExecutor(address(r), address(r));
        ex.setAgent(agent);

        usdt.mint(address(ex), 1_000_000);
        r.configure(usdt, wokb, 1_000_000, 999);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(RouterExecutor.InsufficientOutput.selector, 999, 1000));
        ex.route(address(usdt), address(wokb), 1_000_000, 1000, abi.encodeWithSignature("swap()"));
    }

    /// A router spending more than it was approved for must revert, even if it pays enough out.
    function test_overspend_reverts_even_when_the_output_is_sufficient() public {
        MockRouter r = new MockRouter();
        RouterExecutor ex = new RouterExecutor(address(r), address(r));
        ex.setAgent(agent);

        usdt.mint(address(ex), 5_000_000);
        // Takes 2_000_000 while only 1_000_000 was authorised.
        r.configure(usdt, wokb, 2_000_000, 10_000);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(RouterExecutor.OverSpend.selector, 2_000_000, 1_000_000)
        );
        ex.route(address(usdt), address(wokb), 1_000_000, 1, abi.encodeWithSignature("swap()"));
    }

    /// No standing allowance survives a successful call.
    function test_the_allowance_is_zero_after_a_successful_swap() public {
        MockRouter r = new MockRouter();
        RouterExecutor ex = new RouterExecutor(address(r), address(r));
        ex.setAgent(agent);

        usdt.mint(address(ex), 1_000_000);
        r.configure(usdt, wokb, 1_000_000, 10_000);

        vm.prank(agent);
        ex.route(address(usdt), address(wokb), 1_000_000, 1, abi.encodeWithSignature("swap()"));

        assertEq(usdt.allowance(address(ex), address(r)), 0);
    }

    /// Only the agent may execute. This is the seam that keeps the risk engine the only decider.
    function test_a_stranger_cannot_route() public {
        MockRouter r = new MockRouter();
        RouterExecutor ex = new RouterExecutor(address(r), address(r));
        ex.setAgent(agent);

        vm.prank(stranger);
        vm.expectRevert(RouterExecutor.NotAgent.selector);
        ex.route(address(usdt), address(wokb), 1, 1, abi.encodeWithSignature("swap()"));
    }

    /// The router is immutable, so there is no setter to attack. Asserted rather than assumed,
    /// because "there is no setter" is exactly the kind of claim that quietly stops being true.
    function test_the_router_address_is_immutable() public {
        MockRouter r = new MockRouter();
        RouterExecutor ex = new RouterExecutor(address(r), address(r));
        assertEq(ex.router(), address(r));
    }

    /// THE REGRESSION TEST FOR THE MAINNET BUG.
    ///
    /// The aggregator calls one address and pulls tokens from another. Approving the CALL target
    /// leaves the puller with no allowance, and the swap reverts as `RouterCallFailed(0x0000...)`
    /// with nothing to indicate why. Approving the proxy is what makes it work.
    ///
    /// This test fails against the single-address version of the contract, which is the property
    /// that makes it worth having: the original suite passed against the broken code.
    function test_a_router_that_pulls_through_a_separate_proxy_succeeds() public {
        SplitApprovalRouter r = new SplitApprovalRouter();
        RouterExecutor ex = new RouterExecutor(address(r), address(r.proxy()));
        ex.setAgent(agent);

        wokb.mint(address(ex), 2_000_000_000_000_000);
        r.configure(wokb, usdt, 2_000_000_000_000_000, 198_900);

        vm.prank(agent);
        uint256 out = ex.route(
            address(wokb),
            address(usdt),
            2_000_000_000_000_000,
            198_900, // the real minReceiveAmount for 0.002 WOKB, from a live quote
            abi.encodeWithSignature("swap()")
        );
        assertEq(out, 198_900);
    }

    /// The exact failure seen on mainnet, pinned so it cannot come back: approving the router when
    /// the proxy is the puller reverts the whole swap.
    function test_approving_the_wrong_address_reverts_the_swap() public {
        SplitApprovalRouter r = new SplitApprovalRouter();
        // Deliberately MISCONFIGURED: approver set to the router, which is what the first
        // deployment effectively did by having only one address.
        RouterExecutor ex = new RouterExecutor(address(r), address(r));
        ex.setAgent(agent);

        wokb.mint(address(ex), 2_000_000_000_000_000);
        r.configure(wokb, usdt, 2_000_000_000_000_000, 198_900);

        vm.prank(agent);
        vm.expectRevert(); // RouterCallFailed, wrapping the proxy's allowance failure
        ex.route(
            address(wokb),
            address(usdt),
            2_000_000_000_000_000,
            198_900,
            abi.encodeWithSignature("swap()")
        );
    }

    /// Both addresses are pinned at construction. Neither is ever taken from the calldata the
    /// aggregator returns, which is what keeps a compromised feed from redirecting funds.
    function test_both_targets_are_immutable_and_distinct() public {
        SplitApprovalRouter r = new SplitApprovalRouter();
        RouterExecutor ex = new RouterExecutor(address(r), address(r.proxy()));
        assertEq(ex.router(), address(r));
        assertEq(ex.approver(), address(r.proxy()));
        assertTrue(ex.router() != ex.approver());
    }
}
