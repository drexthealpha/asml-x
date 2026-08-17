// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title CapAccumulator
/// @notice Task 1.5 scribble target. A minimal accumulator carrying the SAME invariant
///         shape as RiskGuard's per-market cap, annotated in scribble's specification
///         language so the annotation compiles to a runtime assertion.
///
/// Why a separate small contract rather than annotating RiskGuard directly:
/// scribble rewrites the source it instruments. Pointing it at RiskGuard would produce an
/// instrumented copy competing with the deployed original, and the deployed bytecode is
/// what every onchain claim in this project rests on. A dedicated target proves the tool
/// works on our invariant shape without touching the contract that is already live and
/// already proven by halmos and hevm.
///
/// The invariant: total can never exceed cap. This is RiskGuard's `exposureOf[market] <=
/// maxPerMarket[market]` reduced to its smallest honest form.
contract CapAccumulator {
    uint256 public total;
    uint256 public immutable cap;

    constructor(uint256 _cap) {
        cap = _cap;
    }

    /// #if_succeeds {:msg "total never exceeds cap"} total <= cap;
    function add(uint256 amount) external {
        total += amount;
    }

    /// #if_succeeds {:msg "total never underflows"} total <= old(total);
    function subtract(uint256 amount) external {
        total -= amount;
    }
}
