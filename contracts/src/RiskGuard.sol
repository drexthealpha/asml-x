// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title RiskGuard
/// @notice The binding authority for exposure limits and the kill switch.
///         The Rust engine is the pre-check. This contract is the last word, so
///         "risk controls can and do stop the agent" is verifiable by anyone with
///         an explorer rather than by trusting our offchain code.
///
/// Design notes that matter for the Phase 3 formal verification:
/// - Exposure is tracked per market and in aggregate, and the aggregate is
///   maintained incrementally so `gross()` is O(1). The invariant that the
///   aggregate equals the sum of parts is therefore a real property to prove, not
///   a tautology.
/// - The agent role can only ever REDUCE its own permissions. It cannot clear the
///   kill switch, cannot raise a cap, and cannot remove itself from the guard.
/// - All arithmetic is unsigned with explicit checks. Solidity 0.8 reverts on
///   overflow, and the caps are far below any overflow boundary.
contract RiskGuard {
    /// @notice Owner can configure caps and clear the kill switch. Intended to be
    ///         a human operator, never the agent.
    address public owner;

    /// @notice The agent may record fills and engage the kill switch. It may not
    ///         clear it and may not change caps.
    mapping(address => bool) public isAgent;

    /// @notice Global gross exposure cap, in quote units.
    uint256 public maxGross;

    /// @notice Per-market exposure cap, in quote units. Zero means the market is
    ///         not tradeable, which makes "unknown market" fail closed.
    mapping(bytes32 => uint256) public maxPerMarket;

    /// @notice Current absolute exposure per market, in quote units.
    mapping(bytes32 => uint256) public exposureOf;

    /// @notice Sum of exposureOf across all markets. Maintained incrementally.
    uint256 public gross;

    /// @notice Set of markets that have ever been configured, so the invariant
    ///         test can iterate and compare the sum against `gross`.
    bytes32[] public markets;
    mapping(bytes32 => bool) public knownMarket;

    bool public killed;
    string public killReason;

    event AgentSet(address indexed agent, bool enabled);
    event MarketCapSet(bytes32 indexed market, uint256 cap);
    event MaxGrossSet(uint256 cap);
    event ExposureChanged(bytes32 indexed market, uint256 newExposure, uint256 newGross);
    event Killed(address indexed by, string reason);
    event Revived(address indexed by);

    error NotOwner();
    error NotAgent();
    error IsKilled(string reason);
    error MarketNotConfigured(bytes32 market);
    error MarketCapExceeded(bytes32 market, uint256 attempted, uint256 cap);
    error GrossCapExceeded(uint256 attempted, uint256 cap);
    error ReduceExceedsExposure(bytes32 market, uint256 attempted, uint256 have);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAgent() {
        if (!isAgent[msg.sender]) revert NotAgent();
        _;
    }

    /// @notice Every guarded action passes through here. When killed, everything
    ///         reverts, which is invariant 3.
    modifier notKilled() {
        if (killed) revert IsKilled(killReason);
        _;
    }

    constructor(uint256 _maxGross) {
        owner = msg.sender;
        maxGross = _maxGross;
        emit MaxGrossSet(_maxGross);
    }

    // ---------------------------------------------------------------------
    // Owner configuration. The agent has no path to any of this.
    // ---------------------------------------------------------------------

    function setAgent(address agent, bool enabled) external onlyOwner {
        isAgent[agent] = enabled;
        emit AgentSet(agent, enabled);
    }

    function setMarketCap(bytes32 market, uint256 cap) external onlyOwner {
        if (!knownMarket[market]) {
            knownMarket[market] = true;
            markets.push(market);
        }
        maxPerMarket[market] = cap;
        emit MarketCapSet(market, cap);
    }

    function setMaxGross(uint256 cap) external onlyOwner {
        maxGross = cap;
        emit MaxGrossSet(cap);
    }

    /// @notice Only the owner can clear the kill switch. This is invariant 4 and
    ///         the reason the agent cannot trade its way out of a halt.
    function revive() external onlyOwner {
        killed = false;
        killReason = "";
        emit Revived(msg.sender);
    }

    // ---------------------------------------------------------------------
    // Agent surface. Can halt, can record, can never loosen.
    // ---------------------------------------------------------------------

    /// @notice Either role may engage the kill switch. Halting is always allowed,
    ///         even when already halted, because a monitor that cannot halt is
    ///         worse than useless.
    function kill(string calldata reason) external {
        if (msg.sender != owner && !isAgent[msg.sender]) revert NotAgent();
        killed = true;
        killReason = reason;
        emit Killed(msg.sender, reason);
    }

    /// @notice Record new exposure from a fill. Reverts if any cap would break,
    ///         which is invariants 1 and 2.
    /// @dev `virtual` so RwaRiskGuard can layer instrument-specific refusals on top
    ///      without reimplementing the cap arithmetic that is already formally
    ///      proven and mutation-tested. Extending rather than forking keeps the
    ///      Phase 3 theorems valid for the RWA path too.
    function addExposure(bytes32 market, uint256 amount) external virtual onlyAgent notKilled {
        _addExposureChecked(market, amount);
    }

    /// @dev The cap arithmetic, factored out so a subclass can add refusals in front
    ///      of it without duplicating it. Duplicated cap logic is how two guards end
    ///      up disagreeing after one of them is patched.
    function _addExposureChecked(bytes32 market, uint256 amount) internal {
        uint256 cap = maxPerMarket[market];
        if (cap == 0) revert MarketNotConfigured(market);

        uint256 nextMarket = exposureOf[market] + amount;
        if (nextMarket > cap) revert MarketCapExceeded(market, nextMarket, cap);

        uint256 nextGross = gross + amount;
        if (nextGross > maxGross) revert GrossCapExceeded(nextGross, maxGross);

        exposureOf[market] = nextMarket;
        gross = nextGross;
        emit ExposureChanged(market, nextMarket, nextGross);
    }

    /// @notice Reduce exposure when a position closes. Allowed while killed,
    ///         deliberately: de-risking must never be blocked by a halt.
    function reduceExposure(bytes32 market, uint256 amount) external virtual onlyAgent {
        _reduceExposureChecked(market, amount);
    }

    function _reduceExposureChecked(bytes32 market, uint256 amount) internal {
        uint256 have = exposureOf[market];
        if (amount > have) revert ReduceExceedsExposure(market, amount, have);
        exposureOf[market] = have - amount;
        gross -= amount;
        emit ExposureChanged(market, have - amount, gross);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function marketCount() external view returns (uint256) {
        return markets.length;
    }

    /// @notice Recomputed sum, for invariant 5. Deliberately O(n) and separate
    ///         from `gross` so the two can be compared. If they ever disagree,
    ///         the incremental accounting is broken.
    function sumOfParts() external view returns (uint256 total) {
        uint256 n = markets.length;
        for (uint256 i = 0; i < n; ++i) {
            total += exposureOf[markets[i]];
        }
    }

    function headroom(bytes32 market) external view returns (uint256) {
        uint256 cap = maxPerMarket[market];
        uint256 used = exposureOf[market];
        uint256 marketRoom = cap > used ? cap - used : 0;
        uint256 grossRoom = maxGross > gross ? maxGross - gross : 0;
        return marketRoom < grossRoom ? marketRoom : grossRoom;
    }
}
