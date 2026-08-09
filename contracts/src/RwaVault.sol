// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title RwaVault
/// @notice SELF-DEPLOYED STAND-IN for an RWA-linked instrument. NOT a real asset,
///         NOT a third-party protocol. Deployed because task 0.4 established that
///         no RWA-linked instrument is live on X Layer testnet, and the alternative
///         was to plan strategies against something that does not exist.
///         Every surface that displays this instrument must carry the
///         SELF-DEPLOYED STAND-IN provenance badge. See ADR-009.
///
/// What it models, and why each one changes agent behaviour:
/// - An ORACLE price with a last-update timestamp. RWA marks come from offchain
///   attestation, not from a live order book, so oracle age is a first-class risk.
///   A generic bot reads a price; an RWA-aware agent reads a price and its age.
/// - A REDEMPTION WINDOW. Primary redemption is only open periodically. Exposure
///   taken just before a window closes cannot be exited at par for a full cycle.
/// - An ISSUER PAUSE flag. A real issuer can halt transfers or redemption. An agent
///   that ignores this can be long an asset it cannot exit.
/// - A YIELD INDEX that accrues. The instrument earns while held, which changes the
///   arithmetic of holding versus flattening.
///
/// What it deliberately does NOT model, stated rather than implied: no credit
/// events, no NAV haircuts, no legal wrapper, no KYC gating on transfer, no
/// secondary-market fee schedule.
contract RwaVault {
    address public immutable issuer;

    /// @notice Oracle price in quote units per 1e18 of the instrument.
    uint256 public oraclePrice;
    /// @notice Block timestamp of the last oracle update.
    uint256 public oracleUpdatedAt;

    /// @notice When true, the issuer has halted the instrument.
    bool public paused;

    /// @notice Redemption window schedule. Windows open every `windowPeriod`
    ///         seconds and stay open for `windowLength` seconds.
    uint256 public windowPeriod;
    uint256 public windowLength;
    uint256 public immutable epochStart;

    /// @notice Yield index, 1e18 = 1.0. Monotonically non-decreasing.
    uint256 public yieldIndex;

    event OraclePriceSet(uint256 price, uint256 at);
    event PausedSet(bool paused);
    event YieldAccrued(uint256 newIndex);
    event WindowScheduleSet(uint256 period, uint256 length);

    error NotIssuer();
    error YieldCannotDecrease(uint256 current, uint256 attempted);
    error ZeroPrice();

    modifier onlyIssuer() {
        if (msg.sender != issuer) revert NotIssuer();
        _;
    }

    constructor(uint256 initialPrice, uint256 _windowPeriod, uint256 _windowLength) {
        if (initialPrice == 0) revert ZeroPrice();
        issuer = msg.sender;
        oraclePrice = initialPrice;
        oracleUpdatedAt = block.timestamp;
        windowPeriod = _windowPeriod;
        windowLength = _windowLength;
        epochStart = block.timestamp;
        yieldIndex = 1e18;
        emit OraclePriceSet(initialPrice, block.timestamp);
        emit WindowScheduleSet(_windowPeriod, _windowLength);
    }

    function setOraclePrice(uint256 price) external onlyIssuer {
        if (price == 0) revert ZeroPrice();
        oraclePrice = price;
        oracleUpdatedAt = block.timestamp;
        emit OraclePriceSet(price, block.timestamp);
    }

    /// @notice Refresh the timestamp without changing the price. Used to prove the
    ///         difference between a stale oracle and a flat one, which a naive
    ///         staleness check cannot distinguish.
    function touchOracle() external onlyIssuer {
        oracleUpdatedAt = block.timestamp;
        emit OraclePriceSet(oraclePrice, block.timestamp);
    }

    function setPaused(bool p) external onlyIssuer {
        paused = p;
        emit PausedSet(p);
    }

    function setWindowSchedule(uint256 period, uint256 length) external onlyIssuer {
        windowPeriod = period;
        windowLength = length;
        emit WindowScheduleSet(period, length);
    }

    /// @notice Yield can only ever increase. An index that could fall would let the
    ///         issuer silently reprice held exposure downward.
    function accrueYield(uint256 newIndex) external onlyIssuer {
        if (newIndex < yieldIndex) revert YieldCannotDecrease(yieldIndex, newIndex);
        yieldIndex = newIndex;
        emit YieldAccrued(newIndex);
    }

    // ---------------------------------------------------------------------
    // Views the agent reads every cycle
    // ---------------------------------------------------------------------

    function oracleAge() external view returns (uint256) {
        return block.timestamp - oracleUpdatedAt;
    }

    /// @notice Seconds until the next redemption window opens. Zero while a window
    ///         is currently open.
    function secondsUntilWindow() external view returns (uint256) {
        if (windowPeriod == 0) return 0;
        uint256 elapsed = (block.timestamp - epochStart) % windowPeriod;
        if (elapsed < windowLength) return 0; // window is open now
        return windowPeriod - elapsed;
    }

    function redemptionOpen() external view returns (bool) {
        if (windowPeriod == 0) return true;
        return ((block.timestamp - epochStart) % windowPeriod) < windowLength;
    }

    /// @notice Everything the risk layer needs, in one call, so the agent's view
    ///         cannot be assembled from reads taken at different blocks.
    function riskView()
        external
        view
        returns (
            uint256 price,
            uint256 age,
            bool isPaused,
            bool isRedemptionOpen,
            uint256 untilWindow,
            uint256 index
        )
    {
        price = oraclePrice;
        age = block.timestamp - oracleUpdatedAt;
        isPaused = paused;
        uint256 elapsed = windowPeriod == 0 ? 0 : (block.timestamp - epochStart) % windowPeriod;
        isRedemptionOpen = windowPeriod == 0 || elapsed < windowLength;
        untilWindow = (windowPeriod == 0 || elapsed < windowLength) ? 0 : windowPeriod - elapsed;
        index = yieldIndex;
    }
}
