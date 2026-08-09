// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Ping
/// @notice Phase 0 liveness proof for ASML-X on X Layer testnet (chain 1952).
///         Exists only to produce a real deploy and a real state-changing
///         transaction with a real explorer link, per standing rule R6.
///         Not part of the product. Superseded by the Phase 2 risk guard.
contract Ping {
    uint256 public count;
    address public immutable deployer;

    event Pinged(address indexed caller, uint256 newCount, uint256 blockNumber);

    constructor() {
        deployer = msg.sender;
    }

    function ping() external returns (uint256) {
        count += 1;
        emit Pinged(msg.sender, count, block.number);
        return count;
    }
}
