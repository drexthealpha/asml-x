// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title BatchExecutor
/// @notice Atomic multi-leg execution. A quote, take, and hedge sequence either
///         fully lands or fully reverts, so a mid-sequence failure cannot leave
///         orphan exposure.
///
/// Why this exists rather than sending three separate transactions: on a chain
/// with ~1s blocks, three separate transactions have two windows in which the
/// second or third can fail while the first has already moved tokens. That is the
/// exact failure the risk engine would then have to unwind. Atomicity removes the
/// window instead of handling it.
///
/// The agent calls this. The RiskGuard call is placed FIRST in the leg list by the
/// offchain executor, so a cap breach reverts the whole sequence before any token
/// moves. That ordering is enforced by a check here, not left to convention.
contract BatchExecutor {
    struct Leg {
        address target;
        bytes data;
    }

    address public immutable owner;
    address public immutable riskGuard;

    event BatchExecuted(address indexed caller, uint256 legCount, bytes32 indexed batchId);
    event LegExecuted(bytes32 indexed batchId, uint256 index, address target, bool success);

    error NotOwner();
    error EmptyBatch();
    error FirstLegMustBeRiskGuard(address got, address want);
    error LegFailed(uint256 index, address target, bytes returndata);

    constructor(address _riskGuard) {
        owner = msg.sender;
        riskGuard = _riskGuard;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Execute legs in order, reverting everything if any leg reverts.
    /// @param batchId Offchain decision journal id, so the onchain event ties
    ///        back to the reasoning that produced the batch.
    function execute(Leg[] calldata legs, bytes32 batchId)
        external
        onlyOwner
        returns (bytes[] memory results)
    {
        if (legs.length == 0) revert EmptyBatch();

        // The guard must be consulted before anything moves. Enforced, because a
        // convention that is only documented is a convention that gets broken.
        if (legs[0].target != riskGuard) {
            revert FirstLegMustBeRiskGuard(legs[0].target, riskGuard);
        }

        results = new bytes[](legs.length);
        for (uint256 i = 0; i < legs.length; ++i) {
            (bool ok, bytes memory ret) = legs[i].target.call(legs[i].data);
            if (!ok) revert LegFailed(i, legs[i].target, ret);
            results[i] = ret;
            emit LegExecuted(batchId, i, legs[i].target, ok);
        }

        emit BatchExecuted(msg.sender, legs.length, batchId);
    }
}
