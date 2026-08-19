// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// The subset RouterExecutor needs. Declared here rather than imported, matching the convention in
/// AgentVault.sol and FeeCollector.sol, which each declare the slice they use.
///
/// NOTE the return types. `approve` and `transfer` are declared WITHOUT a return value and called
/// through a low-level helper below, because X Layer's USDT does not return a bool. A standard
/// `IERC20(t).approve(...)` against it reverts on ABI decoding, and USDT is this vault's accounting
/// asset, so getting this wrong would break the exact path this contract exists to serve.
interface IERC20Router {
    function balanceOf(address account) external view returns (uint256);
}

/// @title RouterExecutor
/// @notice Executes agent trades against REAL X Layer liquidity through the OKX Onchain OS router.
///
/// @dev WHY THIS CONTRACT EXISTS.
///
/// Until now the agent executed against an order book this project deployed and seeded. Every
/// number it produced was real in the sense of being on chain, and meaningless in the sense that
/// this project was the only participant. This contract routes the same risk-gated decisions
/// through the aggregator that real X Layer traders use, across Uniswap V3/V4, PotatoSwap,
/// Revoswap, Caliber and the rest.
///
/// THE DANGEROUS PART, NAMED. Forwarding third-party calldata is the single most dangerous thing
/// this system does. `data` is opaque: it can be any call the router understands, and parsing it
/// here would be a guess about a contract this project does not control. So safety does NOT come
/// from trusting OKX or from inspecting the bytes. It comes from three checks that hold even if
/// the calldata is entirely hostile:
///
///   1. THE ROUTER IS PINNED. `router` is immutable and set at construction. A compromised feed
///      handing back a different `to` address cannot be executed, because this contract never
///      accepts a target from the caller at all.
///   2. THE APPROVAL IS EXACT AND REVOKED. The router is approved for exactly `amountIn` for the
///      duration of one call and reset to zero immediately after, in the same transaction. There
///      is never a standing allowance to drain.
///   3. THE OUTPUT IS MEASURED, NOT REPORTED. Balances of both tokens are read before and after.
///      The call reverts unless this contract actually gained at least `minOut` of `tokenOut` and
///      spent no more than `amountIn` of `tokenIn`. A router that under-delivers, or calldata that
///      swaps the wrong pair, or a partial fill, all revert here.
///
/// Point 3 is the load-bearing one. It converts "trust the aggregator" into "verify the result",
/// which is the same posture the rest of this system takes toward its own agent.
///
/// WHAT THIS CONTRACT DELIBERATELY DOES NOT DO. It does not decide anything. It has no view of the
/// market, no scoring, no limits of its own. `onlyAgent` is the seam: the Rust risk engine is the
/// only thing that can produce an approved action, and this contract is the only thing that can
/// turn one into a swap. Splitting them means a bug in the agent cannot become a bug in custody.
contract RouterExecutor {
    /// @notice The OKX Onchain OS aggregator router on X Layer. Immutable by design.
    address public immutable router;

    /// @notice The contract that PULLS the tokens, which is not the router.
    ///
    /// @dev A REAL BUG, found on mainnet and worth recording rather than quietly patching.
    ///
    /// The first version approved `router` and called `router`, on the reasonable assumption that
    /// the contract being called is the contract doing the pulling. OKX splits them: the router at
    /// 0x722db4... executes the swap, but tokens are pulled by a separate token-approval proxy at
    /// 0x8b773D..., returned by `/api/v6/dex/aggregator/approve-transaction`. With the allowance on
    /// the wrong address the proxy's transferFrom reverts, and the router surfaces it as an
    /// uninformative `RouterCallFailed(0x0000...)`.
    ///
    /// The unit tests did not catch it because MockRouter pulled tokens directly, which quietly
    /// encoded the same wrong assumption the contract made. A mock that shares the contract's
    /// misconception cannot falsify it; `SplitApprovalRouter` in the test file now models the two
    /// addresses separately, and it fails against the old single-address logic.
    ///
    /// STILL IMMUTABLE, and still pinned. Two addresses, both fixed at construction, neither ever
    /// taken from calldata. The security property is unchanged: a compromised feed cannot redirect
    /// funds, because nothing it returns is used as a target or a spender.
    address public immutable approver;

    /// @notice The address allowed to execute. Set to the batch executor or the agent EOA.
    address public agent;

    /// @notice Contract owner, able to rotate the agent and rescue tokens.
    address public owner;

    /// @notice Emitted for every executed swap, with MEASURED amounts, never reported ones.
    event Routed(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minOut
    );

    event AgentSet(address indexed agent);

    error NotOwner();
    error NotAgent();
    error ZeroAddress();
    error RouterCallFailed(bytes reason);
    error TokenCallFailed();
    /// @dev Carries both numbers so a failure is diagnosable from the revert alone.
    error InsufficientOutput(uint256 received, uint256 minOut);
    error OverSpend(uint256 spent, uint256 allowed);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAgent() {
        if (msg.sender != agent) revert NotAgent();
        _;
    }

    /// @dev Call a token method that may or may not return a bool.
    ///
    /// X Layer's USDT (`USD₮0`) follows the original Tether ABI and returns NOTHING from `approve`
    /// and `transfer`. Solidity's generated call decodes a `bool` return and reverts on empty
    /// returndata, so a normal typed call against it fails on a correct token. This accepts either
    /// shape: no returndata is success, and returndata is required to decode as `true`.
    function _tokenCall(address token, bytes memory data) private {
        (bool ok, bytes memory ret) = token.call(data);
        if (!ok) revert TokenCallFailed();
        if (ret.length != 0 && !abi.decode(ret, (bool))) revert TokenCallFailed();
    }

    function _approve(address token, address spender, uint256 amount) private {
        _tokenCall(token, abi.encodeWithSignature("approve(address,uint256)", spender, amount));
    }

    constructor(address router_, address approver_) {
        if (router_ == address(0) || approver_ == address(0)) revert ZeroAddress();
        router = router_;
        approver = approver_;
        owner = msg.sender;
    }

    function setAgent(address agent_) external onlyOwner {
        if (agent_ == address(0)) revert ZeroAddress();
        agent = agent_;
        emit AgentSet(agent_);
    }

    /// @notice Execute one aggregator swap, verifying the result rather than trusting it.
    /// @param tokenIn   Token spent. Must already be held by this contract.
    /// @param tokenOut  Token expected. Verified by balance delta.
    /// @param amountIn  Exact amount the router is approved for, and the ceiling on what it spends.
    /// @param minOut    Minimum acceptable gain of `tokenOut`. Comes from the aggregator's own
    ///                  `minReceiveAmount`, which the risk engine may only ever TIGHTEN.
    /// @param data      Opaque router calldata. Never parsed, never trusted, always verified.
    /// @return amountOut The measured gain in `tokenOut`.
    function route(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        bytes calldata data
    ) external onlyAgent returns (uint256 amountOut) {
        if (tokenIn == address(0) || tokenOut == address(0)) revert ZeroAddress();

        uint256 inBefore = IERC20Router(tokenIn).balanceOf(address(this));
        uint256 outBefore = IERC20Router(tokenOut).balanceOf(address(this));

        // EXACT approval for the duration of one call. Some tokens (USDT among them) revert on a
        // non-zero to non-zero approve, so it is zeroed first. This is not defensive noise: USDT is
        // the vault's accounting asset on this chain.
        _approve(tokenIn, approver, 0);
        _approve(tokenIn, approver, amountIn);

        (bool ok, bytes memory reason) = router.call(data);
        if (!ok) revert RouterCallFailed(reason);

        // Revoked in the SAME transaction, so no allowance survives this call under any path that
        // does not revert everything.
        _approve(tokenIn, approver, 0);

        uint256 inAfter = IERC20Router(tokenIn).balanceOf(address(this));
        uint256 outAfter = IERC20Router(tokenOut).balanceOf(address(this));

        // Underflow-safe by construction: a swap cannot increase tokenIn, but if hostile calldata
        // somehow did, `spent` would underflow and revert, which is the correct outcome.
        uint256 spent = inBefore - inAfter;
        if (spent > amountIn) revert OverSpend(spent, amountIn);

        amountOut = outAfter - outBefore;
        if (amountOut < minOut) revert InsufficientOutput(amountOut, minOut);

        emit Routed(tokenIn, tokenOut, amountIn, amountOut, minOut);
    }

    /// @notice Recover tokens. Owner-only, and deliberately present: this contract holds real value
    ///         between legs of a trade, and a stuck balance with no exit would be a worse flaw than
    ///         the privilege this introduces.
    function rescue(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        _tokenCall(token, abi.encodeWithSignature("transfer(address,uint256)", to, amount));
    }
}
