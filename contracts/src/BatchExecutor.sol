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

    /// @notice The fee collector every batch must pay. Immutable, so no operator can point a batch
    ///         at a different collector or at address(0).
    address public immutable feeCollector;

    event BatchExecuted(address indexed caller, uint256 legCount, bytes32 indexed batchId);
    event LegExecuted(bytes32 indexed batchId, uint256 index, address target, bool success);

    error NotOwner();
    error EmptyBatch();
    error FirstLegMustBeRiskGuard(address got, address want);
    error LegFailed(uint256 index, address target, bytes returndata);
    error LastLegMustBeFeeCollector(address got, address want);

    constructor(address _riskGuard, address _feeCollector) {
        owner = msg.sender;
        riskGuard = _riskGuard;
        feeCollector = _feeCollector;
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

        // The fee must be the LAST leg, so it is charged on the notional that actually executed
        // rather than on one that a later leg might revert. Same reasoning as the guard-first rule,
        // applied at the other end of the batch: an operator who could omit this leg would have a
        // fee-free execution path, and then "the fee cannot be skipped" would be a slogan.
        if (legs[legs.length - 1].target != feeCollector) {
            revert LastLegMustBeFeeCollector(legs[legs.length - 1].target, feeCollector);
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

    /// @notice Approve a spender to pull a token held by this contract.
    ///
    /// This exists because of a problem the unit tests could not surface. The executor holds the
    /// quote asset and must approve both the venue and the FeeCollector to pull from it. In a Foundry
    /// test that is a `vm.prank(address(exec))`, which is a cheat with no onchain equivalent: a
    /// contract cannot be impersonated on a real chain, so without this function the deployed
    /// executor could never grant either allowance and every batch would revert at the first pull.
    /// Found by writing the deploy script rather than by running the suite, which is the argument for
    /// treating deployment as part of the design instead of a step at the end.
    ///
    /// It is `onlyOwner`, and it grants an allowance rather than moving tokens, so the worst an owner
    /// can do with it is what an owner can already do by directing a batch.
    function approveToken(address token, address spender, uint256 amount) external onlyOwner {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount)); // approve(address,uint256)
        if (!ok) revert LegFailed(type(uint256).max, token, ret);
    }
}
