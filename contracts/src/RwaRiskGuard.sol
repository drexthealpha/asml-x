// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RiskGuard} from "./RiskGuard.sol";
import {RwaVault} from "./RwaVault.sol";

/// @title RwaRiskGuard
/// @notice The RiskGuard plus refusals that only make sense for an RWA-linked
///         instrument. Extends rather than forks, so every cap theorem proven in
///         Phase 3 still holds on this path.
///
/// Four refusals a generic guard does not have. Each one is a real failure mode of
/// tokenized real-world assets, not a decoration:
///
/// 1. STALE ORACLE. An RWA mark is an attestation, not a traded price. Past a
///    threshold age the mark is a guess, so new exposure is refused. Note the
///    asymmetry with `reduceExposure`, which stays open: being unable to add is
///    inconvenient, being unable to exit is dangerous.
/// 2. ISSUER PAUSED. If the issuer has halted the instrument, new exposure buys
///    something that cannot currently be exited.
/// 3. REDEMPTION WINDOW PROXIMITY. Exposure added shortly before a window closes is
///    locked for a full cycle, so size is refused inside a configurable buffer.
/// 4. ORACLE VERSUS MARKET DIVERGENCE. When the secondary price the agent observes
///    diverges from the oracle beyond a tolerance, one of the two is wrong and the
///    correct action is to stop adding, not to pick a side.
contract RwaRiskGuard is RiskGuard {
    RwaVault public immutable vault;

    /// @notice Maximum tolerated oracle age in seconds.
    uint256 public maxOracleAge;
    /// @notice Refuse new exposure when a redemption window opens within this many
    ///         seconds, because entering just before a lockup is the trap.
    uint256 public windowBufferSeconds;
    /// @notice Maximum tolerated divergence between oracle and observed market
    ///         price, in basis points.
    uint256 public maxDivergenceBps;
    /// @notice Last observed secondary market price, submitted by the agent and
    ///         compared against the oracle. Stored so the divergence check is
    ///         evaluated onchain rather than trusted from offchain.
    uint256 public observedMarketPrice;
    uint256 public observedMarketAt;

    event RwaPolicySet(uint256 maxOracleAge, uint256 windowBuffer, uint256 maxDivergenceBps);
    event MarketPriceObserved(uint256 price, uint256 at);
    event RwaRefusal(bytes32 indexed market, string reason);

    error OracleStale(uint256 age, uint256 maxAge);
    error IssuerPaused();
    error RedemptionWindowTooClose(uint256 untilWindow, uint256 buffer);
    error OracleMarketDivergence(uint256 divergenceBps, uint256 maxBps);
    error NoObservedMarketPrice();

    constructor(
        uint256 _maxGross,
        address _vault,
        uint256 _maxOracleAge,
        uint256 _windowBufferSeconds,
        uint256 _maxDivergenceBps
    ) RiskGuard(_maxGross) {
        vault = RwaVault(_vault);
        maxOracleAge = _maxOracleAge;
        windowBufferSeconds = _windowBufferSeconds;
        maxDivergenceBps = _maxDivergenceBps;
        emit RwaPolicySet(_maxOracleAge, _windowBufferSeconds, _maxDivergenceBps);
    }

    function setRwaPolicy(
        uint256 _maxOracleAge,
        uint256 _windowBufferSeconds,
        uint256 _maxDivergenceBps
    ) external onlyOwner {
        maxOracleAge = _maxOracleAge;
        windowBufferSeconds = _windowBufferSeconds;
        maxDivergenceBps = _maxDivergenceBps;
        emit RwaPolicySet(_maxOracleAge, _windowBufferSeconds, _maxDivergenceBps);
    }

    /// @notice The agent reports the secondary price it observed. Recorded onchain so
    ///         the divergence refusal is enforced by the contract, not by the agent's
    ///         good intentions.
    function observeMarketPrice(uint256 price) external onlyAgent {
        observedMarketPrice = price;
        observedMarketAt = block.timestamp;
        emit MarketPriceObserved(price, block.timestamp);
    }

    /// @notice Divergence between oracle and last observed market price, in bps.
    function divergenceBps() public view returns (uint256) {
        uint256 oracle = vault.oraclePrice();
        if (oracle == 0 || observedMarketPrice == 0) return 0;
        uint256 diff = observedMarketPrice > oracle
            ? observedMarketPrice - oracle
            : oracle - observedMarketPrice;
        return (diff * 10_000) / oracle;
    }

    /// @notice The RWA pre-check, public so the UI and the demo can query exactly
    ///         what the guard would say without sending a transaction.
    function rwaTradeable() public view returns (bool ok, string memory reason) {
        (, uint256 age, bool isPaused, , uint256 untilWindow, ) = vault.riskView();

        if (isPaused) return (false, "issuer has paused the instrument");
        if (age > maxOracleAge) return (false, "oracle mark is stale");
        if (untilWindow > 0 && untilWindow <= windowBufferSeconds) {
            return (false, "redemption window opens too soon to take new exposure");
        }
        if (observedMarketPrice != 0 && divergenceBps() > maxDivergenceBps) {
            return (false, "oracle and observed market price diverge");
        }
        return (true, "");
    }

    /// @notice String-free version of `rwaTradeable`, for the symbolic prover.
    ///
    /// Halmos cannot execute MCOPY (opcode 0x5e), which Solidity emits when returning
    /// a `string memory`. Any proof that called `rwaTradeable` therefore aborted with
    /// an internal error rather than a counterexample. This view carries the same
    /// decision with no string, so the properties are provable. It is not a
    /// workaround wrapper hiding a defect: both functions read the same state through
    /// the same branches, and a test below asserts they never disagree.
    function rwaTradeableFlag() public view returns (bool) {
        (, uint256 age, bool isPaused, , uint256 untilWindow, ) = vault.riskView();
        if (isPaused) return false;
        if (age > maxOracleAge) return false;
        if (untilWindow > 0 && untilWindow <= windowBufferSeconds) return false;
        if (observedMarketPrice != 0 && divergenceBps() > maxDivergenceBps) return false;
        return true;
    }

    /// @notice Same cap arithmetic as the base guard, with the RWA refusals first.
    ///
    /// Order matters: the instrument-specific checks run BEFORE the generic caps, so
    /// the revert reason a judge or operator sees names the actual cause rather than
    /// a downstream symptom.
    function addExposure(bytes32 market, uint256 amount) external override onlyAgent notKilled {
        (, uint256 age, bool isPaused, , uint256 untilWindow, ) = vault.riskView();

        if (isPaused) {
            emit RwaRefusal(market, "issuer paused");
            revert IssuerPaused();
        }
        if (age > maxOracleAge) {
            emit RwaRefusal(market, "oracle stale");
            revert OracleStale(age, maxOracleAge);
        }
        if (untilWindow > 0 && untilWindow <= windowBufferSeconds) {
            emit RwaRefusal(market, "redemption window too close");
            revert RedemptionWindowTooClose(untilWindow, windowBufferSeconds);
        }
        if (observedMarketPrice != 0) {
            uint256 div = divergenceBps();
            if (div > maxDivergenceBps) {
                emit RwaRefusal(market, "oracle market divergence");
                revert OracleMarketDivergence(div, maxDivergenceBps);
            }
        }

        _addExposureChecked(market, amount);
    }

    /// @notice De-risking is NEVER blocked by an RWA condition.
    ///
    /// This is the deliberate asymmetry. A stale oracle or a paused issuer is
    /// exactly when an agent most needs to reduce, and a guard that blocks the exit
    /// converts a risk control into a trap.
    function reduceExposure(bytes32 market, uint256 amount) external override onlyAgent {
        _reduceExposureChecked(market, amount);
    }
}
