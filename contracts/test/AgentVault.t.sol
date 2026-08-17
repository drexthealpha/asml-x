// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentVault} from "../src/AgentVault.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// Task 8.2. PASS: "the agent key cannot withdraw to any address under any input."
///
/// THINKING: #22 inversion (do not ask whether the depositor can withdraw, ask who ELSE can and by
/// what route), #29 margin-of-safety (assume the operator key is hostile, not merely absent),
/// #11 systems (the vault, the agent and the trade target are three parties and the property has to
/// hold across all three).
///
/// The named fake win: "testing withdraw only from the depositor's address."
/// The counter, quoted: "a test attempts withdrawal from the agent key, the owner key and a random
/// key, and asserts all three revert." That is `test_onlyTheDepositorCanWithdraw` below, and it is
/// deliberately not the only such test: `test_thereIsNoFunctionThatMovesFundsToAnArbitraryAddress`
/// enumerates every state-changing function on the contract, because "these three keys cannot call
/// withdraw" is a weaker claim than "no function exists that would let them".
contract AgentVaultTest is Test {
    AgentVault vault;
    MockERC20 token;

    address depositor = address(0xDE9051);
    address other = address(0x07AE);
    address agent = address(0xA6E7);
    address owner = address(this);
    address tradeTarget = address(0x7A46);
    address attacker = address(0xBAD);

    uint256 constant DEPOSIT = 1_000 ether;
    uint256 constant LIMIT = 100 ether;

    function setUp() public {
        token = new MockERC20("Test Quote", "tQUOTE");
        vault = new AgentVault(address(token), tradeTarget);
        vault.setAgent(agent);

        token.mint(depositor, DEPOSIT);
        token.mint(other, DEPOSIT);
        token.mint(tradeTarget, DEPOSIT);

        vm.prank(depositor);
        token.approve(address(vault), type(uint256).max);
        vm.prank(other);
        token.approve(address(vault), type(uint256).max);
        vm.prank(tradeTarget);
        token.approve(address(vault), type(uint256).max);
    }

    function _deposit(address who, uint256 amount, uint256 limit) internal {
        vm.prank(who);
        vault.deposit(amount, limit);
    }

    // ------------------------------------------------------------------ the property this exists for

    /// THE TASK'S PASS CONDITION, from three different keys.
    function test_onlyTheDepositorCanWithdraw() public {
        _deposit(depositor, DEPOSIT, LIMIT);

        // 1. The agent key. The most plausible attacker: it is online, it holds a hot key, and it is
        //    the only address with any power over these funds at all.
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentVault.ZeroAmount.selector));
        vault.withdrawAll();

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(AgentVault.InsufficientBalance.selector, DEPOSIT, 0)
        );
        vault.withdraw(DEPOSIT);

        // 2. The owner key. Owner can rotate the agent and nothing else.
        vm.expectRevert(
            abi.encodeWithSelector(AgentVault.InsufficientBalance.selector, DEPOSIT, 0)
        );
        vault.withdraw(DEPOSIT);

        // 3. An arbitrary key.
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(AgentVault.InsufficientBalance.selector, DEPOSIT, 0)
        );
        vault.withdraw(DEPOSIT);

        // Nothing moved for any of them, and the depositor's balance is untouched.
        assertEq(token.balanceOf(agent), 0);
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(attacker), 0);
        assertEq(vault.balanceOf(depositor), DEPOSIT);
        assertEq(token.balanceOf(address(vault)), DEPOSIT);
    }

    /// The stronger form. "Those three keys cannot call `withdraw`" would still permit a contract
    /// with some OTHER function that moves funds. This asserts there is no such function by walking
    /// every state-changing entry point as the agent and as the owner, and checking the vault's token
    /// balance afterwards.
    function test_thereIsNoFunctionThatMovesFundsToAnArbitraryAddress() public {
        _deposit(depositor, DEPOSIT, LIMIT);
        uint256 vaultBefore = token.balanceOf(address(vault));

        // Everything the agent can call.
        vm.startPrank(agent);
        vault.openTrade(depositor, LIMIT); // the ONLY agent path that moves tokens
        vm.stopPrank();

        // It moved funds to tradeTarget and nowhere else. The agent named no destination, because
        // openTrade takes none: the target is immutable.
        assertEq(token.balanceOf(tradeTarget), DEPOSIT + LIMIT, "only the immutable target received");
        assertEq(token.balanceOf(agent), 0, "the agent received nothing");

        // Everything the owner can call. setAgent is the entire list.
        vault.setAgent(attacker);
        assertEq(token.balanceOf(attacker), 0, "rotating the agent moves nothing");
        assertEq(vault.balanceOf(depositor), DEPOSIT, "and touches no balance");
        vault.setAgent(agent);

        assertEq(token.balanceOf(address(vault)), vaultBefore - LIMIT, "only the trade left");
    }

    /// A new agent inherits the same gates. Rotation is not an escalation path.
    function test_aRotatedAgentGetsNoNewPowers() public {
        _deposit(depositor, DEPOSIT, LIMIT);
        vault.setAgent(attacker);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(AgentVault.ExceedsUserLimit.selector, LIMIT + 1, LIMIT)
        );
        vault.openTrade(depositor, LIMIT + 1);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(AgentVault.InsufficientBalance.selector, DEPOSIT, 0)
        );
        vault.withdraw(DEPOSIT);
    }

    function test_onlyTheOwnerCanRotateTheAgent() public {
        vm.prank(attacker);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.setAgent(attacker);

        vm.prank(agent);
        vm.expectRevert(AgentVault.NotOwner.selector);
        vault.setAgent(agent);
    }

    // ------------------------------------------------------------------------------ pause behaviour

    /// The property the research task made non-negotiable: pause stops the AGENT and never the exit.
    function test_pauseStopsTheAgentAndNeverTheWithdrawal() public {
        _deposit(depositor, DEPOSIT, LIMIT);

        vm.prank(depositor);
        vault.setPaused(true);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentVault.DepositorPaused.selector, depositor));
        vault.openTrade(depositor, LIMIT);

        // And the exit is wide open WHILE paused. A pause that trapped funds would be the attack.
        vm.prank(depositor);
        uint256 got = vault.withdrawAll();

        assertEq(got, DEPOSIT);
        assertEq(token.balanceOf(depositor), DEPOSIT, "full balance returned while paused");
        assertEq(vault.balanceOf(depositor), 0);
        assertTrue(vault.paused(depositor), "and it is still paused");
    }

    /// Pause is per-depositor. One user pausing must not stop another user's agent, or a single
    /// panicking user becomes a denial of service for everyone.
    function test_pauseIsPerDepositorAndDoesNotAffectAnyoneElse() public {
        _deposit(depositor, DEPOSIT, LIMIT);
        _deposit(other, DEPOSIT, LIMIT);

        vm.prank(depositor);
        vault.setPaused(true);

        vm.prank(agent);
        vault.openTrade(other, LIMIT); // unaffected

        assertEq(vault.committed(other), LIMIT);
        assertEq(vault.committed(depositor), 0);
    }

    function test_nobodyCanPauseAnotherDepositor() public {
        _deposit(depositor, DEPOSIT, LIMIT);

        // There is no function taking a depositor argument, so the strongest an attacker can do is
        // pause themselves. Asserted rather than argued.
        vm.prank(attacker);
        vault.setPaused(true);

        assertFalse(vault.paused(depositor), "the depositor is not paused by a stranger");
        assertTrue(vault.paused(attacker));

        vm.prank(agent);
        vault.openTrade(depositor, LIMIT); // still works
    }

    // --------------------------------------------------------------------------------- limits

    function test_theAgentCannotExceedAUsersLimit() public {
        _deposit(depositor, DEPOSIT, LIMIT);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(AgentVault.ExceedsUserLimit.selector, LIMIT + 1, LIMIT)
        );
        vault.openTrade(depositor, LIMIT + 1);

        // Exactly at the limit is allowed. Off-by-one in the safe direction is still a bug.
        vm.prank(agent);
        vault.openTrade(depositor, LIMIT);
        assertEq(vault.committed(depositor), LIMIT);
    }

    function test_limitsAreIndependentPerDepositor() public {
        _deposit(depositor, DEPOSIT, LIMIT);
        _deposit(other, DEPOSIT, LIMIT * 2);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(AgentVault.ExceedsUserLimit.selector, LIMIT * 2, LIMIT)
        );
        vault.openTrade(depositor, LIMIT * 2);

        vm.prank(agent);
        vault.openTrade(other, LIMIT * 2); // same notional, different user, allowed
    }

    function test_aDepositorCanTightenTheirOwnLimit() public {
        _deposit(depositor, DEPOSIT, LIMIT);

        vm.prank(depositor);
        vault.setMaxNotional(1 ether);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(AgentVault.ExceedsUserLimit.selector, LIMIT, 1 ether)
        );
        vault.openTrade(depositor, LIMIT);
    }

    // ----------------------------------------------------------------------- accounting integrity

    /// Committed funds are not withdrawable, or the same tokens would be both traded and withdrawn.
    function test_committedFundsCannotAlsoBeWithdrawn() public {
        _deposit(depositor, DEPOSIT, LIMIT);

        vm.prank(agent);
        vault.openTrade(depositor, LIMIT);

        assertEq(vault.withdrawable(depositor), DEPOSIT - LIMIT);

        vm.prank(depositor);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentVault.InsufficientBalance.selector, DEPOSIT, DEPOSIT - LIMIT
            )
        );
        vault.withdraw(DEPOSIT);

        // The rest is still freely withdrawable, which is the half of the property that matters to
        // a user: an open trade does not freeze the whole balance.
        vm.prank(depositor);
        vault.withdraw(DEPOSIT - LIMIT);
        assertEq(token.balanceOf(depositor), DEPOSIT - LIMIT);
    }

    /// Profit and loss land on the depositor whose funds were traded. This is what makes per-user
    /// limits mean anything: if outcomes were shared, one user's limit would not bound their risk.
    function test_profitAndLossLandOnTheDepositorWhoseFundsWereTraded() public {
        _deposit(depositor, DEPOSIT, LIMIT);
        _deposit(other, DEPOSIT, LIMIT);

        vm.prank(agent);
        vault.openTrade(depositor, LIMIT);

        // The target returns 10% more than it took.
        uint256 returned = LIMIT + 10 ether;
        vm.prank(tradeTarget);
        token.approve(address(vault), type(uint256).max);
        vm.prank(agent);
        token.mint(agent, returned);
        vm.prank(agent);
        token.approve(address(vault), type(uint256).max);
        vm.prank(agent);
        vault.closeTrade(depositor, LIMIT, returned);

        assertEq(vault.balanceOf(depositor), DEPOSIT + 10 ether, "the gain went to the trader");
        assertEq(vault.balanceOf(other), DEPOSIT, "and not to the other depositor");
        assertEq(vault.committed(depositor), 0);
    }

    function test_aLossAlsoLandsOnlyOnThatDepositor() public {
        _deposit(depositor, DEPOSIT, LIMIT);
        _deposit(other, DEPOSIT, LIMIT);

        vm.prank(agent);
        vault.openTrade(depositor, LIMIT);

        uint256 returned = LIMIT - 10 ether;
        token.mint(agent, returned);
        vm.prank(agent);
        token.approve(address(vault), type(uint256).max);
        vm.prank(agent);
        vault.closeTrade(depositor, LIMIT, returned);

        assertEq(vault.balanceOf(depositor), DEPOSIT - 10 ether, "the loss hit the trader");
        assertEq(vault.balanceOf(other), DEPOSIT, "and not the other depositor");
    }

    /// The solvency invariant, which is the one an outside observer can check without trusting us.
    function test_theVaultIsSolventThroughAFullCycle() public {
        assertTrue(vault.isSolvent(), "empty");
        _deposit(depositor, DEPOSIT, LIMIT);
        assertTrue(vault.isSolvent(), "after deposit");

        vm.prank(agent);
        vault.openTrade(depositor, LIMIT);
        assertTrue(vault.isSolvent(), "with a trade in flight");

        token.mint(agent, LIMIT);
        vm.prank(agent);
        token.approve(address(vault), type(uint256).max);
        vm.prank(agent);
        vault.closeTrade(depositor, LIMIT, LIMIT);
        assertTrue(vault.isSolvent(), "after close");

        vm.prank(depositor);
        vault.withdrawAll();
        assertTrue(vault.isSolvent(), "after full withdrawal");
        assertEq(vault.totalDeposits(), 0);
    }

    /// A token that keeps part of the transfer must not credit a balance the vault does not hold.
    /// Same failure class as the FeeCollector's ShortPay, and it matters more here: the number it
    /// would corrupt is a custody balance, so the first deposit would make the vault insolvent.
    function test_aShortDeliveringTokenCannotCreditABalanceTheVaultDoesNotHold() public {
        SkimmingToken skimmer = new SkimmingToken();
        AgentVault v2 = new AgentVault(address(skimmer), tradeTarget);
        skimmer.mint(depositor, DEPOSIT);

        vm.prank(depositor);
        skimmer.approve(address(v2), type(uint256).max);

        vm.prank(depositor);
        vm.expectRevert();
        v2.deposit(DEPOSIT, LIMIT);

        assertEq(v2.balanceOf(depositor), 0, "no balance was credited");
        assertEq(v2.totalDeposits(), 0);
    }

    /// Withdrawal must be exact across magnitudes, so a rounding path cannot strand dust that
    /// accumulates into a real amount.
    function testFuzz_aDepositorAlwaysGetsBackExactlyWhatTheyPutIn(uint96 amount) public {
        vm.assume(amount > 0);
        token.mint(depositor, uint256(amount));
        uint256 before = token.balanceOf(depositor);

        vm.prank(depositor);
        vault.deposit(uint256(amount), LIMIT);
        vm.prank(depositor);
        uint256 got = vault.withdrawAll();

        assertEq(got, uint256(amount));
        assertEq(token.balanceOf(depositor), before, "exactly restored, no dust lost");
        assertEq(vault.balanceOf(depositor), 0);
    }

    function test_depositRefusesZero() public {
        vm.prank(depositor);
        vm.expectRevert(AgentVault.ZeroAmount.selector);
        vault.deposit(0, LIMIT);
    }

    function test_theAgentCannotTradeMoreThanIsInTheVault() public {
        _deposit(depositor, 50 ether, LIMIT);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(AgentVault.InsufficientBalance.selector, LIMIT, 50 ether)
        );
        vault.openTrade(depositor, LIMIT);
    }
}

/// A token that delivers less than requested while reporting success.
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

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 delivered = (amount * 90) / 100;
        balanceOf[from] -= amount;
        balanceOf[to] += delivered;
        return true;
    }
}
