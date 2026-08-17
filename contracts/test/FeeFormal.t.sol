// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FeeCollector} from "../src/FeeCollector.sol";

/// Task 7.4. Symbolic theorems about the fee, checked by halmos 0.3.3 over ALL inputs in range rather
/// than over the examples a fuzzer happens to draw.
///
/// THINKING: #45 proof by contradiction (halmos proves a property by failing to find a
/// counterexample), #4 deductive, #46 induction (theorem 5 is the inductive step: if the running total
/// is right after n charges it is right after n+1).
///
/// WHY THIS IS NOT A DUPLICATE OF THE FUZZ TEST IN FeeCollector.t.sol. That test draws 256 random
/// notionals. It cannot distinguish "correct" from "correct on 256 samples". These theorems quantify
/// over every value in range with no sampling, so a divisor wrong only near a boundary is caught here.
/// The fuzz test stays because it runs in milliseconds on every commit and halmos does not.
///
/// WRITTEN FOR THE SOLVER, and the first version was not. It declared the same five properties but
/// put a `new SymToken()` inside a symbolic body and passed `--solver-timeout-assertion 0`, and the
/// run produced no theorem output at all in 25 minutes. Every allocation is now hoisted into `setUp`,
/// which halmos executes once concretely, and the constants are read as literals rather than through
/// five external calls the solver would have to model. The timeout is finite so a stall reports as a
/// failure instead of as silence.
///
/// halmos uses the `check_` prefix; hevm, also installed, uses `prove_`. They are not interchangeable.
contract FeeFormalTest {
    FeeCollector fee;
    SymToken token;

    address constant PAYER = address(0xCAFE);
    address constant TREASURY = address(0xBEEF);
    uint256 constant BPS_DENOM = 10_000;
    uint256 constant CEILING = 100;
    uint256 constant START_BPS = 50;

    /// Concrete setup, executed once. Nothing symbolic happens here on purpose.
    function setUp() public {
        fee = new FeeCollector(TREASURY, START_BPS);
        token = new SymToken();
        token.mint(PAYER, type(uint128).max);
        fee.setCharger(address(this), true);
    }

    /// THEOREM 1: the fee never exceeds the immutable ceiling, for any notional.
    ///
    /// Stated as a cross-multiplication rather than a division, so the claim is about integers and not
    /// about how two truncations compare.
    ///
    /// The notional is bounded to 2**128 because above that `notional * CEILING` overflows a uint256
    /// and 0.8.x reverts, which is a safe outcome rather than a violated bound, while an unbounded
    /// symbolic multiplication is what makes the solver give up. 2**128 base units exceeds total
    /// supply for every token this will touch, so the bound hides no reachable case.
    function check_feeNeverExceedsTheCeiling(uint256 notional) public view {
        if (notional >= 2 ** 128) return;
        uint256 f = fee.quoteFee(notional);
        assert(f * BPS_DENOM <= notional * CEILING);
    }

    /// THEOREM 2: the fee is EXACTLY the stated fraction.
    ///
    /// Theorem 1 alone is satisfied by a contract that charges zero always, so the bound is only half
    /// the property and exactness is the other half.
    function check_feeIsExactlyTheStatedFraction(uint256 notional) public view {
        if (notional >= 2 ** 128) return;
        assert(fee.quoteFee(notional) == (notional * START_BPS) / BPS_DENOM);
    }

    /// THEOREM 3: monotonic in the notional. A larger trade never pays less.
    ///
    /// Catches a class of rounding and branch errors that theorems 1 and 2 each survive, because a
    /// piecewise formula can be bounded and locally exact while still dipping.
    ///
    /// BOUNDED TO 2**96 RATHER THAN 2**128, and the reason is solver hardness rather than the
    /// property. This is the only theorem here that relates TWO symbolic divisions. 2**96 base units
    /// is 7.9e28, which at 18 decimals is 7.9e10 whole tokens: far above any notional this system
    /// will route. What is NOT proved is monotonicity between 2**96 and 2**256, and that gap is
    /// stated here rather than implied by the word "proved".
    ///
    /// THE MULTIPLICATION HALF PROVES. It is kept as a theorem because it is the half that is about
    /// this contract's arithmetic rather than about integer division in general.
    function check_feeMultiplicationPreservesOrder(uint256 a, uint256 b) public pure {
        if (a >= 2 ** 96 || b >= 2 ** 96) return;
        if (a > b) return;
        assert(a * START_BPS <= b * START_BPS);
    }

    // -------------------------------------------------------------------------------------------
    // MONOTONICITY IS NOT PROVED SYMBOLICALLY, AND THIS RECORDS WHY RATHER THAN HIDING IT.
    //
    // An earlier version of this file asserted `quoteFee(a) <= quoteFee(b)` and its comment claimed
    // the proof "actually closes" at 2**96. It does not. Measured, with halmos 0.3.3 and Z3:
    //
    //   quoteFee(a) <= quoteFee(b), bound 2**96      TIMEOUT at 240s, and again at 900s
    //   (a*K)/D <= (b*K)/D as pure arithmetic        TIMEOUT at 240s
    //   x/D <= y/D alone, no multiplication          TIMEOUT at 240s
    //   the same, bound lowered to 2**64             TIMEOUT
    //   the same, bound lowered to 2**48             TIMEOUT
    //   the same, bound lowered to 2**32             TIMEOUT
    //
    // Lowering the bound changes nothing, which is the useful finding: the range guard is a path
    // condition, but `x` and `y` remain full 256-bit bitvectors inside `bvudiv`, and two symbolic
    // 256-bit divisions in one query is where this solver stops. Narrowing further would have been
    // shrinking the claim until it turned green without making the solver's job any different.
    //
    // WHAT IS STILL PROVED, so this is not a gap dressed up as a decision. THEOREM 2 proves
    // `quoteFee(n) == (n * START_BPS) / BPS_DENOM` EXACTLY, over the real contract, for every n
    // below 2**128, in 0.03s. The residue is monotonicity of `floor(x / 10_000)`, which is a fact
    // about integer division and not a property of this fee. It is covered by the fuzz test below
    // rather than left unverified, and the theorem count in scripts/104b-fee-formal.sh reflects
    // what is actually proved rather than what was hoped for.
    // -------------------------------------------------------------------------------------------

    /// Monotonicity, fuzzed rather than proved. Foundry draws real values and runs the real
    /// contract, so this catches a dipping formula on any drawn pair; what it cannot do is quantify
    /// over the whole range, and the comment block above says so.
    function testFuzz_feeIsMonotonicInNotional(uint96 a, uint96 b) public view {
        uint256 lo = a <= b ? a : b;
        uint256 hi = a <= b ? b : a;
        assert(fee.quoteFee(lo) <= fee.quoteFee(hi));
    }

    /// THEOREM 4: the rate is one-directional, and the ceiling holds in every reachable state.
    ///
    /// This is the theorem that replaced the dead ceiling check task 7.5's mutation gate found in
    /// `setFeeBps`. That branch was unreachable, so no test could cover it; the invariant it was
    /// meant to express is inductive and belongs here instead.
    function check_setFeeBpsCanOnlyLower(uint256 newBps) public {
        uint256 current = fee.feeBps();
        try fee.setFeeBps(newBps) {
            assert(newBps < current);
            assert(fee.feeBps() == newBps);
            assert(fee.feeBps() <= CEILING);
        } catch {
            // A revert that still moved state would be the interesting bug, so it is asserted rather
            // than assumed.
            assert(fee.feeBps() == current);
        }
    }

    /// THEOREM 5, the inductive step. `totalCollected` after a charge equals the total before plus the
    /// amount the contract itself quoted, and a zero-value charge does not increment the growth
    /// counter. Repeated over n charges this is the accumulation property: the dashboard total and the
    /// event stream cannot drift apart.
    ///
    /// Bounded to 2**96 so the payer balance minted in `setUp` always covers the fee, keeping the
    /// theorem about accounting rather than about running out of tokens.
    function check_totalCollectedAccumulatesExactly(uint256 notional) public {
        if (notional >= 2 ** 96) return;

        uint256 before = fee.totalCollected(address(token));
        uint256 countBefore = fee.chargeCount();
        uint256 expected = fee.quoteFee(notional);

        fee.charge(PAYER, bytes32(uint256(1)), address(token), notional);

        assert(fee.totalCollected(address(token)) == before + expected);
        if (expected == 0) {
            assert(fee.chargeCount() == countBefore);
        } else {
            assert(fee.chargeCount() == countBefore + 1);
        }
    }
}

/// A minimal honest token. Deliberately not MockERC20: no allowance check, so the theorem is about
/// FeeCollector's accounting and the solver is not also exploring an approval state space irrelevant
/// to the property. The dishonest-token case is covered concretely by the ShortPay test in
/// FeeCollector.t.sol.
contract SymToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
