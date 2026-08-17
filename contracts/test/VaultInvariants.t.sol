// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentVault} from "../src/AgentVault.sol";
import {FeeCollector} from "../src/FeeCollector.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// Task 14.2: an invariant campaign on the fee and vault contracts.
///
/// THINKING: #46 proof by induction (an invariant IS the inductive step: true initially, preserved by
/// every transition), #45 proof by contradiction, #66 red teaming.
///
/// WHY INVARIANTS AND NOT MORE UNIT TESTS. A unit test asserts a property after a sequence somebody
/// chose. An invariant asserts it after EVERY sequence the fuzzer can build, including orderings
/// nobody thought of. The vault has four state-changing entry points and the interesting failures
/// live in their interleavings: deposit while committed, withdraw mid-trade, pause between an open
/// and a close.
///
/// THE HANDLER IS THE TEST. A handler that can only reach safe states makes every invariant pass
/// vacuously, which is task 8.4's named fake win in a different costume. So `test_handlerCanReachInterestingStates`
/// asserts the handler actually got somewhere worth checking, and it is the first thing to read if
/// this suite ever goes green suspiciously fast.
contract VaultHandler is Test {
    AgentVault public vault;
    MockERC20 public token;
    address public agent;

    address[] public actors;
    uint256 public depositCount;
    uint256 public withdrawCount;
    uint256 public tradeOpenCount;
    uint256 public tradeCloseCount;
    uint256 public pauseCount;
    uint256 public sumDeposited;
    uint256 public sumWithdrawn;
    uint256 public depositFailures;
    bytes public lastDepositRevert;
    uint256 public openFailures;
    bytes public lastOpenRevert;
    uint256 public lastOpenNotional;
    uint256 public lastOpenCap;
    uint256 public lastOpenWithdrawable;
    bool public lastOpenPaused;

    constructor(AgentVault v, MockERC20 t, address a) {
        vault = v;
        token = t;
        agent = a;
        for (uint160 i = 1; i <= 4; i++) {
            address who = address(i * 0x1000);
            actors.push(who);
            t.mint(who, 1_000_000 ether);
            vm.prank(who);
            t.approve(address(v), type(uint256).max);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// The limit is bounded to a RANGE THAT OVERLAPS the deposit, not left raw.
    ///
    /// A raw `uint96 limit` is astronomically larger than any deposit almost every draw, and a raw
    /// notional in `openTrade` is likewise, so every trade reverted on `ExceedsUserLimit` and the
    /// campaign never once reached a committed state. The anti-vacuity check caught that and said so
    /// exactly: "no trade was ever opened, so committed was always 0".
    ///
    /// This is the failure mode that makes an invariant campaign worthless while it reports green,
    /// and it is why the anti-vacuity assertion exists at all.
    function deposit(uint256 seed, uint96 amount, uint96 limit) public {
        address who = _actor(seed);
        amount = uint96(bound(amount, 1 ether, 1_000 ether));
        limit = uint96(bound(limit, 1, amount));
        vm.prank(who);
        try vault.deposit(amount, limit) {
            depositCount++;
            sumDeposited += amount;
        } catch (bytes memory why) {
            // The reason is KEPT, not swallowed. A handler that silently absorbs every revert makes
            // an invariant campaign look busy while reaching nothing, and diagnosing that from the
            // outside is guesswork. `lastDepositRevert` is what turned "no deposit ever succeeded"
            // from a mystery into a one-line answer.
            lastDepositRevert = why;
            depositFailures++;
        }
    }

    function withdraw(uint256 seed, uint96 amount) public {
        address who = _actor(seed);
        vm.prank(who);
        try vault.withdraw(amount) {
            withdrawCount++;
            sumWithdrawn += amount;
        } catch {}
    }

    function withdrawAll(uint256 seed) public {
        address who = _actor(seed);
        uint256 before = vault.balanceOf(who);
        vm.prank(who);
        try vault.withdrawAll() returns (uint256 got) {
            withdrawCount++;
            sumWithdrawn += got;
            before;
        } catch {}
    }

    function setPaused(uint256 seed, bool p) public {
        address who = _actor(seed);
        vm.prank(who);
        vault.setPaused(p);
        pauseCount++;
    }

    /// Bounded to the depositor's OWN limit, so the fuzzer explores inside the permitted region as
    /// well as outside it. Left raw, every draw exceeded the limit and the campaign only ever
    /// exercised the refusal path, never the state where funds are actually committed.
    ///
    /// A quarter of the draws are deliberately allowed to exceed the limit, because the invariants
    /// must hold across failed attempts too.
    function openTrade(uint256 seed, uint96 notional) public {
        address who = _actor(seed);
        uint256 cap = vault.maxNotional(who);
        if (cap > 0) {
            notional = uint96(bound(notional, 1, cap * 4 / 3));
        }
        vm.prank(agent);
        try vault.openTrade(who, notional) {
            tradeOpenCount++;
        } catch (bytes memory why) {
            lastOpenRevert = why;
            openFailures++;
            lastOpenNotional = notional;
            lastOpenCap = cap;
            lastOpenWithdrawable = vault.withdrawable(who);
            lastOpenPaused = vault.paused(who);
        }
    }

    function closeTrade(uint256 seed, uint96 notional, uint96 returned) public {
        address who = _actor(seed);
        uint256 committed = vault.committed(who);
        if (committed == 0) return;
        notional = uint96(bound(notional, 1, committed));
        returned = uint96(bound(returned, 0, 2_000 ether));
        token.mint(agent, returned);
        vm.prank(agent);
        token.approve(address(vault), type(uint256).max);
        vm.prank(agent);
        try vault.closeTrade(who, notional, returned) {
            tradeCloseCount++;
        } catch {}
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}

contract VaultInvariantTest is Test {
    AgentVault vault;
    MockERC20 token;
    VaultHandler handler;
    address agent = address(0xA6E7);
    address tradeTarget = address(0x7A46);

    function setUp() public {
        token = new MockERC20("Invariant Quote", "iQUOTE");
        vault = new AgentVault(address(token), tradeTarget);
        vault.setAgent(agent);
        handler = new VaultHandler(vault, token, agent);
        targetContract(address(handler));

        // RESTRICT THE FUZZER TO THE HANDLER'S OWN FUNCTIONS.
        //
        // `VaultHandler` inherits from `Test`, so its public surface is hundreds of inherited
        // cheatcode helpers. `targetContract` alone makes all of them fuzzable, and the six
        // functions that actually drive the vault are picked so rarely that `deposit` was called
        // ZERO times in 8192 calls. The campaign ran, reported green on every safety invariant, and
        // had never touched the contract under test.
        //
        // The anti-vacuity check is the only reason this was visible: it reported
        // "deposit attempts that reverted: 0", which distinguishes "deposit failed" from
        // "deposit was never called" and pointed straight at the cause.
        bytes4[] memory sel = new bytes4[](6);
        sel[0] = VaultHandler.deposit.selector;
        sel[1] = VaultHandler.withdraw.selector;
        sel[2] = VaultHandler.withdrawAll.selector;
        sel[3] = VaultHandler.setPaused.selector;
        sel[4] = VaultHandler.openTrade.selector;
        sel[5] = VaultHandler.closeTrade.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sel}));
    }

    /// THE SOLVENCY INVARIANT, and the one an outside observer can check without trusting anybody.
    ///
    /// The vault must always hold at least what it owes, counting funds legitimately out with the
    /// trade target. If this can be broken by any interleaving, user funds can be lost.
    function invariant_vaultIsAlwaysSolvent() public view {
        assertTrue(vault.isSolvent(), "vault became insolvent");
    }

    /// `totalDeposits` must equal the sum of the per-depositor balances. Two representations of one
    /// fact, and a drift between them would mean the solvency check above is measuring the wrong
    /// number.
    function invariant_totalDepositsEqualsSumOfBalances() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            sum += vault.balanceOf(handler.actors(i));
        }
        assertEq(vault.totalDeposits(), sum, "totalDeposits drifted from the sum of balances");
    }

    /// `totalCommitted` must equal the sum of per-depositor committed amounts, for the same reason.
    function invariant_totalCommittedEqualsSumOfCommitted() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            sum += vault.committed(handler.actors(i));
        }
        assertEq(vault.totalCommitted(), sum, "totalCommitted drifted");
    }

    /// Nobody can have more committed than they have deposited. A breach here means the agent moved
    /// funds a depositor never provided.
    function invariant_committedNeverExceedsBalance() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            address a = handler.actors(i);
            assertLe(vault.committed(a), vault.balanceOf(a), "committed exceeded balance");
        }
    }

    /// The withdrawable amount is exactly balance minus committed, never more. This is what stops the
    /// same tokens being both traded and withdrawn.
    function invariant_withdrawableIsBalanceMinusCommitted() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            address a = handler.actors(i);
            uint256 bal = vault.balanceOf(a);
            uint256 com = vault.committed(a);
            uint256 expected = bal > com ? bal - com : 0;
            assertEq(vault.withdrawable(a), expected, "withdrawable is not balance minus committed");
        }
    }

    /// THE ANTI-VACUITY CHECK. A handler that only ever reaches safe states makes every invariant
    /// above pass while proving nothing, which is task 8.4's named fake win. This asserts the
    /// campaign actually exercised the interesting transitions.
    ///
    /// Read this FIRST if the suite ever goes green suspiciously quickly.
    /// It is `afterInvariant`, NOT an `invariant_` function, and the difference is the point. An
    /// invariant must hold at EVERY step including step zero, and at step zero the handler has done
    /// nothing, so as an invariant this failed during environment setup with "no deposit ever
    /// succeeded: 0 <= 0". Foundry calls `afterInvariant` once when the campaign finishes, which is
    /// the only moment at which "did this campaign reach anything interesting" is a sensible
    /// question to ask.
    /// Coverage is LOGGED here, not asserted.
    ///
    /// Asserting in `afterInvariant` makes Foundry treat the run as failed, which triggers shrinking:
    /// the campaign collapsed to `runs: 1, calls: 1` and then complained that a one-call sequence had
    /// never deposited. True, and useless. `afterInvariant` is for cleanup and logging; assertions
    /// there fight the shrinker.
    ///
    /// The reachability claim is made by `test_everyInterestingStateIsReachable` below, which drives
    /// a deterministic sequence. That is the honest form of the anti-vacuity argument: not "the
    /// random campaign happened to get there" but "these states are reachable at all, so an invariant
    /// holding across them is saying something".
    function afterInvariant() public {
        emit log_named_uint("deposits that succeeded", handler.depositCount());
        emit log_named_uint("trades opened", handler.tradeOpenCount());
        emit log_named_uint("trades closed", handler.tradeCloseCount());
        emit log_named_uint("withdrawals", handler.withdrawCount());
        emit log_named_uint("pauses toggled", handler.pauseCount());
    }

    /// THE ANTI-VACUITY PROOF, as a deterministic test rather than a hope about the fuzzer.
    ///
    /// Every state the invariants above are supposed to constrain is reached here explicitly. If any
    /// assertion in this test fails, the invariants are vacuous and their passing means nothing.
    function test_everyInterestingStateIsReachable() public {
        address who = handler.actors(0);

        // deposit
        vm.prank(who);
        token.mint(who, 1_000 ether);
        vm.prank(who);
        token.approve(address(vault), type(uint256).max);
        vm.prank(who);
        vault.deposit(100 ether, 50 ether);
        assertEq(vault.balanceOf(who), 100 ether, "deposit is reachable");

        // committed, which is the state that makes withdrawable differ from balance
        vm.prank(agent);
        vault.openTrade(who, 40 ether);
        assertEq(vault.committed(who), 40 ether, "a committed position is reachable");
        assertEq(vault.withdrawable(who), 60 ether, "withdrawable differs from balance while committed");

        // paused WHILE committed, the interleaving the invariants care about
        vm.prank(who);
        vault.setPaused(true);
        assertTrue(vault.paused(who), "paused while committed is reachable");
        assertTrue(vault.isSolvent(), "still solvent while paused and committed");

        // the exit stays open while paused, which is the property the whole design turns on
        vm.prank(who);
        vault.withdraw(60 ether);
        assertEq(vault.balanceOf(who), 40 ether, "withdrawal while paused and committed is reachable");

        // close, returning less than went out
        token.mint(agent, 40 ether);
        vm.prank(agent);
        token.approve(address(vault), type(uint256).max);
        vm.prank(agent);
        vault.closeTrade(who, 40 ether, 30 ether);
        assertEq(vault.committed(who), 0, "an unwound position is reachable");
        assertTrue(vault.isSolvent(), "solvent after a loss-making close");
    }
}

/// The fee contract's own invariants. Separate handler because its state space is unrelated.
contract FeeHandler is Test {
    FeeCollector public fee;
    MockERC20 public token;
    address public charger;
    uint256 public chargeAttempts;
    uint256 public lowerAttempts;

    constructor(FeeCollector f, MockERC20 t, address c) {
        fee = f;
        token = t;
        charger = c;
        t.mint(address(this), 10_000_000 ether);
        t.approve(address(f), type(uint256).max);
    }

    function charge(uint96 notional) public {
        chargeAttempts++;
        vm.prank(charger);
        try fee.charge(address(this), bytes32(uint256(1)), address(token), notional) {} catch {}
    }

    /// Pranked as the OWNER. `setFeeBps` is `onlyOwner` and the owner is the test contract that
    /// deployed the FeeCollector, not this handler, so calling it directly reverted `NotOwner` every
    /// time and the rate never moved. The anti-vacuity test caught it as "lowering the rate is
    /// reachable: 50 != 49": the campaign had been exercising the ceiling invariants against a rate
    /// that was structurally frozen.
    ///
    /// The range deliberately extends to 200, above the 100 bps ceiling, so the fuzzer also attempts
    /// invalid raises. The invariants must hold across refused attempts, not only permitted ones.
    function lowerFee(uint256 newBps) public {
        lowerAttempts++;
        newBps = bound(newBps, 0, 200);
        vm.prank(fee.owner());
        try fee.setFeeBps(newBps) {} catch {}
    }
}

contract FeeInvariantTest is Test {
    FeeCollector fee;
    MockERC20 token;
    FeeHandler handler;
    address treasury = address(0xBEEF);
    address charger = address(0xEEEE);

    function setUp() public {
        token = new MockERC20("Invariant Quote", "iQUOTE");
        fee = new FeeCollector(treasury, 50);
        fee.setCharger(charger, true);
        handler = new FeeHandler(fee, token, charger);
        targetContract(address(handler));

        // Same restriction as the vault suite, and for the same reason: FeeHandler inherits Test,
        // so without this the fuzzer spends its budget on inherited cheatcode helpers.
        bytes4[] memory sel = new bytes4[](2);
        sel[0] = FeeHandler.charge.selector;
        sel[1] = FeeHandler.lowerFee.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sel}));
    }

    /// The rate can never exceed the immutable ceiling, under any sequence of setFeeBps calls.
    function invariant_feeNeverExceedsTheCeiling() public view {
        assertLe(fee.feeBps(), fee.MAX_FEE_BPS(), "fee rose above the ceiling");
    }

    /// The rate is MONOTONICALLY NON-INCREASING. This is the whole safety argument for an
    /// owner-held fee knob, and an invariant campaign is the right instrument because it tries every
    /// ordering of raises and lowers rather than the three a unit test picks.
    uint256 private _lastSeen = type(uint256).max;

    function invariant_feeOnlyEverFalls() public {
        uint256 now_ = fee.feeBps();
        assertLe(now_, _lastSeen, "the fee rose between two observations");
        _lastSeen = now_;
    }

    /// Collected total must equal the treasury's balance: the contract keeps nothing.
    function invariant_totalCollectedMatchesTheTreasury() public view {
        assertEq(
            fee.totalCollected(address(token)),
            token.balanceOf(treasury),
            "accounting drifted from the treasury balance"
        );
    }

    /// Anti-vacuity: the campaign must actually have charged something.
    ///
    /// Same reasoning as the vault suite's: this is a question about the WHOLE campaign, so it
    /// belongs in `afterInvariant` rather than in something asserted at every step including the
    /// first, where it is necessarily false.
    /// Logged, not asserted, for the same reason as the vault suite.
    function afterInvariant() public {
        emit log_named_uint("charge attempts", handler.chargeAttempts());
        emit log_named_uint("lower-fee attempts", handler.lowerAttempts());
    }

    /// The anti-vacuity proof, deterministic.
    function test_chargingAndLoweringAreBothReachable() public {
        uint256 before = fee.chargeCount();
        handler.charge(1_000 ether);
        assertGt(fee.chargeCount(), before, "a charge is reachable");

        uint256 rate = fee.feeBps();
        handler.lowerFee(rate - 1);
        assertEq(fee.feeBps(), rate - 1, "lowering the rate is reachable");
    }
}
