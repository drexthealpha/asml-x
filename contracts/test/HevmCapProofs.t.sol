// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {RiskGuard} from "../src/RiskGuard.sol";

/// @title HevmCapProofs
/// @notice The cap theorem written for hevm, so a SECOND INDEPENDENT SYMBOLIC ENGINE
///         reaches a verdict on the same property halmos proves.
///
/// Why this file exists separately from RiskGuardSymbolic.t.sol:
/// hevm discovers symbolic tests by the `prove_` prefix. halmos uses `check_`. Running
/// `hevm test` against the halmos suite found zero tests and exited 0, which is the exact
/// "prover verifies nothing and reports success" failure this phase is built to catch.
///
/// It DOES inherit forge-std Test, and that is required rather than stylistic.
/// hevm's own documentation states `hevm test` executes tests "that make use of the
/// std-test assertion library". The first version of this file dropped the inheritance to
/// avoid cheatcodes, and hevm then discovered zero tests and exited 0. The base contract is
/// how hevm identifies a test contract at all.
///
/// It still avoids cheatcode CALLS: no vm.prank, no vm.assume. Engines differ in cheatcode
/// coverage, and a proof that depends on cheatcode support silently changes meaning between
/// engines. Instead:
///   - the test contract makes ITSELF the agent, so no prank is needed
///   - input bounds are plain early returns, which every engine handles identically
/// Inheriting the assertion base while calling no cheatcodes keeps this portable.
contract HevmCapProofs is Test {
    RiskGuard guard;
    bytes32 constant M = keccak256("tBASE/tQUOTE");
    uint256 constant CAP = 400 ether;
    uint256 constant GROSS = 1_000 ether;
    uint256 constant BOUND = 2 ** 96;

    constructor() {
        guard = new RiskGuard(GROSS);
        // This contract is the owner, so it can appoint itself the agent. No prank.
        guard.setAgent(address(this), true);
        guard.setMarketCap(M, CAP);
    }

    /// Per-market exposure can never exceed its cap, for any single amount.
    function prove_capNeverExceeded(uint256 amount) public {
        if (amount == 0 || amount >= BOUND) return;
        try guard.addExposure(M, amount) {} catch {}
        assert(guard.exposureOf(M) <= CAP);
    }

    /// Two sequential adds cannot breach the cap either. This is the case a single-call
    /// proof misses, because the interesting breach is cumulative.
    function prove_capHoldsAcrossTwoAdds(uint256 a, uint256 b) public {
        if (a == 0 || b == 0 || a >= BOUND || b >= BOUND) return;
        try guard.addExposure(M, a) {} catch {}
        try guard.addExposure(M, b) {} catch {}
        assert(guard.exposureOf(M) <= CAP);
        assert(guard.gross() <= GROSS);
    }

    /// Gross exposure always equals the sum of its per-market parts. If these ever
    /// diverge, every cap check downstream is reasoning about a stale total.
    function prove_grossEqualsSumOfParts(uint256 amount) public {
        if (amount == 0 || amount >= BOUND) return;
        try guard.addExposure(M, amount) {} catch {}
        assert(guard.gross() == guard.sumOfParts());
    }

    /// Once killed, no amount can be added. The kill switch is not advisory.
    function prove_killedRefusesEveryAmount(uint256 amount) public {
        if (amount == 0 || amount >= BOUND) return;
        guard.kill("hevm");
        uint256 before = guard.exposureOf(M);
        try guard.addExposure(M, amount) {
            assert(false); // reaching here means a killed guard accepted exposure
        } catch {}
        assert(guard.exposureOf(M) == before);
    }

    /// Reducing can never underflow, and can never leave more than was held.
    function prove_reduceNeverUnderflows(uint256 add, uint256 cut) public {
        if (add == 0 || add > CAP || cut == 0) return;
        try guard.addExposure(M, add) {} catch {}
        uint256 held = guard.exposureOf(M);
        try guard.reduceExposure(M, cut) {} catch {}
        assert(guard.exposureOf(M) <= held);
    }
}
