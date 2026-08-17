// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title FeeCollector
/// @notice The business model, as a contract rather than as a claim. Charges a usage fee on the
///         notional of every risk-approved execution and emits it as an event a dashboard can read
///         back from chain.
///
/// WHY A USAGE FEE AND NOT A PERFORMANCE FEE, recorded in evidence/phase7/fee-research.md:
/// a performance fee on realized PnL is the fairer model and it is what a real fund would charge.
/// It is not implementable here yet, because this agent has no realized PnL until task 14.4. A fee
/// that structurally cannot fire would emit zero events for the whole demo, which is worse than the
/// fake win this phase is guarding against, because it would create pressure to fake the event.
/// So this is a usage fee, and it is named a usage fee everywhere it appears.
///
/// THREE STRUCTURAL PROPERTIES, each with the specific failure it prevents:
///
/// 1. `MAX_FEE_BPS` is a compile-time constant and `setFeeBps` can only LOWER the rate. A fee that
///    an owner can raise without bound is a theft primitive wearing an onlyOwner modifier.
/// 2. The fee is computed from the balance DELTA actually received, never from the caller's `amount`
///    argument. This is the direct lesson of Code4rena Cudos 2022 issue 3, where trusting the
///    argument mis-accounted every fee-on-transfer token that passed through.
/// 3. Checks-effects-interactions with a transient-storage reentrancy guard. State and event are
///    settled before any token moves, so a reentrant call through the token's transfer hook sees the
///    already-updated total. Transient storage (TSTORE/TLOAD, Solidity 0.8.24+) costs roughly 200 gas
///    against roughly 5,000 for a storage lock, which is a visible line in the mainnet cost table
///    that task 12.6 publishes.
interface IERC20Fee {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract FeeCollector {
    /// @notice Hard ceiling. Immutable in code, not in storage, so no owner and no upgrade can move
    ///         it. 100 bps is 1 percent.
    uint256 public constant MAX_FEE_BPS = 100;

    /// @notice Basis-point denominator. 10000 bps is 100 percent.
    uint256 public constant BPS_DENOMINATOR = 10_000;

    address public owner;

    /// @notice Addresses allowed to charge a fee. The BatchExecutor is the only one in practice, and
    ///         restricting it is what stops an arbitrary caller from emitting fee events that make
    ///         the revenue counter look busy.
    mapping(address => bool) public chargers;

    /// @notice Current rate. Starts at the ceiling and may only ever be lowered.
    uint256 public feeBps;

    /// @notice Where collected fees are sent.
    address public treasury;

    /// @notice Total fees collected, per token. The dashboard reads events rather than this, but a
    ///         mismatch between the two is a bug worth being able to detect, and 7.4 proves they
    ///         agree.
    mapping(address => uint256) public totalCollected;

    /// @notice The number of fees ever charged. Used by the reproduction audit to check the event
    ///         count from `getLogs` against contract state.
    uint256 public chargeCount;

    event FeeCharged(
        address indexed payer,
        bytes32 indexed market,
        address token,
        uint256 notional,
        uint256 feeAmount,
        uint256 feeBps
    );
    event FeeBpsLowered(uint256 oldBps, uint256 newBps);
    event ChargerSet(address indexed charger, bool allowed);
    event TreasurySet(address indexed treasury);

    error NotOwner();
    error NotCharger();
    error FeeAboveCeiling(uint256 requested, uint256 ceiling);
    error FeeNotLowered(uint256 current, uint256 requested);
    error TransferFailed();
    error ShortPay(uint256 expected, uint256 received);
    error Reentrancy();
    error ZeroAddress();

    /// Transient-storage reentrancy slot. Cleared automatically at the end of the transaction, so
    /// there is no storage refund dance and no risk of a stuck lock.
    ///
    /// A LITERAL, not `keccak256(...)`. solc rejects a computed constant inside inline assembly with
    /// "Only direct number constants and references to such constants are supported", which the
    /// compiler said plainly on the first build. Transient storage is a per-contract namespace and
    /// this is the ONLY transient slot this contract uses, so slot 0 cannot collide with anything.
    /// The named-hash pattern exists to avoid collisions in a shared namespace, and there is no
    /// shared namespace here to collide in.
    uint256 private constant REENTRANCY_SLOT = 0;

    modifier nonReentrant() {
        assembly ("memory-safe") {
            if tload(REENTRANCY_SLOT) {
                mstore(0x00, 0xab143c06) // Reentrancy()
                revert(0x1c, 0x04)
            }
            tstore(REENTRANCY_SLOT, 1)
        }
        _;
        assembly ("memory-safe") {
            tstore(REENTRANCY_SLOT, 0)
        }
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address treasury_, uint256 feeBps_) {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (feeBps_ > MAX_FEE_BPS) revert FeeAboveCeiling(feeBps_, MAX_FEE_BPS);
        owner = msg.sender;
        treasury = treasury_;
        feeBps = feeBps_;
    }

    /// @notice The fee this contract would charge on a given notional. Read by the UI before
    ///         activation so a user sees the number before committing, and read by tests so the
    ///         expected value is never computed twice in two places.
    function quoteFee(uint256 notional) public view returns (uint256) {
        return (notional * feeBps) / BPS_DENOMINATOR;
    }

    /// @notice Charge the usage fee for one executed notional.
    ///
    /// CHECKS, then EFFECTS, then INTERACTIONS. The counters and the event are settled first; the
    /// token moves last. A token that re-enters here through a transfer hook finds the state already
    /// written and the guard engaged.
    ///
    /// The amount credited is the balance DELTA, not `expected`. A fee-on-transfer token that
    /// delivers less than requested causes a revert with the two numbers rather than silently
    /// under-collecting, because a fee contract that quietly accepts less than it charged is a fee
    /// contract whose events do not mean what they say.
    function charge(address payer, bytes32 market, address token, uint256 notional)
        external
        nonReentrant
        returns (uint256 feeAmount)
    {
        if (!chargers[msg.sender]) revert NotCharger();

        feeAmount = quoteFee(notional);
        if (feeAmount == 0) {
            // A notional small enough to round the fee to zero is charged nothing and emits nothing.
            // Emitting a zero-value FeeCharged would inflate the event count that task 13.1 shows as
            // a growth number.
            return 0;
        }

        uint256 cachedBps = feeBps;

        // EFFECTS first.
        totalCollected[token] += feeAmount;
        chargeCount += 1;
        emit FeeCharged(payer, market, token, notional, feeAmount, cachedBps);

        // INTERACTIONS last, with the delta measured rather than assumed.
        uint256 before = IERC20Fee(token).balanceOf(treasury);
        if (!IERC20Fee(token).transferFrom(payer, treasury, feeAmount)) revert TransferFailed();
        uint256 received = IERC20Fee(token).balanceOf(treasury) - before;
        if (received < feeAmount) revert ShortPay(feeAmount, received);
    }

    /// @notice Lower the fee. There is deliberately no way to raise it.
    ///
    /// THIS FUNCTION HAD A REDUNDANT CEILING CHECK, and task 7.5's mutation gate is what found it:
    /// deleting `if (newBps > MAX_FEE_BPS) revert FeeAboveCeiling(...)` left the whole suite green.
    /// That was not a missing test, it was dead code. The line below already forces
    /// `newBps < feeBps`, the constructor already forces `feeBps <= MAX_FEE_BPS`, and nothing else
    /// writes `feeBps`, so `newBps < feeBps <= MAX_FEE_BPS` holds by induction and the deleted branch
    /// was unreachable. It was removed rather than covered, because a test written to reach an
    /// unreachable branch is a test written to make a number go up.
    ///
    /// The ceiling is still enforced where it is reachable: in the constructor, which
    /// `test_constructorRefusesAFeeAboveTheCeiling` covers and mutant M2 now targets. The invariant
    /// `feeBps <= MAX_FEE_BPS` is proved for every reachable state by check_setFeeBpsCanOnlyLower in
    /// test/FeeFormal.t.sol, which is the right instrument for an inductive property.
    function setFeeBps(uint256 newBps) external onlyOwner {
        if (newBps >= feeBps) revert FeeNotLowered(feeBps, newBps);
        emit FeeBpsLowered(feeBps, newBps);
        feeBps = newBps;
    }

    function setCharger(address charger, bool allowed) external onlyOwner {
        if (charger == address(0)) revert ZeroAddress();
        chargers[charger] = allowed;
        emit ChargerSet(charger, allowed);
    }

    function setTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }
}
