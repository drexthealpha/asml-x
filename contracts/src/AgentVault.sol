// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title AgentVault
/// @notice Custody for user capital that an agent may TRADE but may never MOVE OUT.
///
/// THE ONE PROPERTY THIS CONTRACT EXISTS FOR: tokens leave this contract only to the address that
/// deposited them, and only when that address asks. There is no owner withdrawal, no agent
/// withdrawal, no rescue function, no sweep, no upgrade path. Those are not omissions to be added
/// later; every one of them is an exit the operator could take, and a custody contract with an
/// operator exit is a custody claim with an asterisk.
///
/// DESIGN DECISIONS AND THE SOURCE THAT FORCED EACH, recorded in evidence/phase8/vault-research.md:
///
/// 1. PAUSE NEVER BLOCKS WITHDRAWAL. `pause()` stops the AGENT acting on a depositor's funds and has
///    no effect on that depositor's `withdraw()`. The pausable audit guidance names "pause blocks
///    withdrawals without a safe escape path" as a major red flag, and it is right: a pause that can
///    trap funds turns the safety feature into the attack. Task 8.4 proves withdrawal is independent
///    of pause rather than asserting it here.
///
/// 2. THE PAUSER IS THE DEPOSITOR. The usual anti-pattern is one hot key holding pause and unpause
///    for everybody, whose usual fix is a multisig plus timelock. That fix is unnecessary here
///    because the risk was designed out: pause is per-depositor, so no key exists that can pause
///    everyone, and there is no shared authority to compromise.
///
/// 3. NO TIMER ANY CALLER CAN TOUCH. No cooldown, no withdrawal delay, no timestamp. The
///    `DelayedWithdrawal` griefing finding shows how cheaply a third party resets one. Withdrawal is
///    synchronous. There is nothing to reset because there is nothing to wait for.
///
/// 4. PER-DEPOSITOR BALANCES, NOT ERC-4626 SHARES. Shares price a pool and there is no pool: each
///    depositor sets their own limits and the agent trades each deposit against those limits. A share
///    price over that structure either socialises one user's losses onto another, which would make
///    per-user limits theatre, or duplicates the per-user accounting it sits on top of. It also
///    imports the first-depositor inflation attack for no benefit.
///
/// 5. OUTCOME, NOT INTENT. Balances move on measured token deltas and every transfer is checked, so
///    state can never claim a movement that did not happen.
interface IERC20Vault {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// EIP-2612, the subset AgentVault needs.
interface IERC20Permit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract AgentVault {
    /// @notice The single token this vault custodies. Immutable: a vault whose asset can be changed
    ///         is a vault whose accounting can be pointed at a token nobody deposited.
    address public immutable asset;

    /// @notice The agent permitted to trade. It can move funds only to `tradeTarget`, and cannot
    ///         reach a depositor's balance in any other way.
    address public agent;

    /// @notice The only address the agent may send funds to when trading. Immutable, so the agent
    ///         cannot be redirected at an attacker-chosen contract even by the owner.
    address public immutable tradeTarget;

    /// @notice Deploys the vault. `owner` can rotate the agent and nothing else; it deliberately has
    ///         no power over any depositor's funds.
    address public owner;

    /// @notice Per-depositor token balance. The depositor's tokens, full stop.
    mapping(address => uint256) public balanceOf;

    /// @notice Per-depositor notional ceiling for a single agent action, set at deposit time.
    ///         Enforced here as well as offchain, so the limit is not a promise made by a Rust
    ///         binary the user cannot see.
    mapping(address => uint256) public maxNotional;

    /// @notice Per-depositor pause. True means the agent may not act for this depositor.
    ///         Does NOT affect withdrawal.
    mapping(address => bool) public paused;

    /// @notice Funds currently committed to an in-flight agent action, per depositor. Deducted from
    ///         withdrawable balance so the same tokens cannot be both traded and withdrawn.
    mapping(address => uint256) public committed;

    /// @notice Sum of all depositor balances. Compared against the vault's actual token holdings by
    ///         the solvency theorem in task 8.4 and by `isSolvent()` at runtime.
    uint256 public totalDeposits;

    /// @notice Sum of every depositor's committed amount. Kept as a running total because Solidity
    ///         cannot iterate a mapping, and a solvency check that had to be handed a list of
    ///         depositors by its caller would be a check the caller could pass a short list to.
    uint256 public totalCommitted;

    event Deposited(address indexed depositor, uint256 amount, uint256 maxNotional, uint256 newBalance);
    event Withdrawn(address indexed depositor, uint256 amount, uint256 newBalance);
    event PauseSet(address indexed depositor, bool paused);
    event LimitSet(address indexed depositor, uint256 maxNotional);
    event AgentSet(address indexed agent);
    event TradeOpened(address indexed depositor, uint256 notional);
    /// @dev Carries the two raw amounts rather than a derived signed pnl. See
    ///      scripts/patch_vault_pnl.py: casting an attacker-influenced uint256 to int256 to
    ///      compute a difference is an unsafe typecast, and forge-lint said so.
    event TradeClosed(address indexed depositor, uint256 notional, uint256 returned);

    error NotOwner();
    error NotAgent();
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance(uint256 requested, uint256 available);
    error DepositorPaused(address depositor);
    error ExceedsUserLimit(uint256 requested, uint256 limit);
    error TransferFailed();
    error ShortDeposit(uint256 expected, uint256 received);
    error Reentrancy();
    error NothingCommitted();

    /// Transient-storage reentrancy slot. Slot 0 is safe because transient storage is a per-contract
    /// namespace and this is the only transient slot the contract uses. A computed `keccak256`
    /// constant is rejected by solc inside inline assembly, which FeeCollector.sol records in full.
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

    modifier onlyAgent() {
        if (msg.sender != agent) revert NotAgent();
        _;
    }

    constructor(address asset_, address tradeTarget_) {
        if (asset_ == address(0) || tradeTarget_ == address(0)) revert ZeroAddress();
        asset = asset_;
        tradeTarget = tradeTarget_;
        owner = msg.sender;
    }

    // ------------------------------------------------------------------ depositor-only operations

    /// @notice Deposit tokens and set the per-action notional ceiling for them.
    ///
    /// The credited amount is the MEASURED balance delta, never `amount`. A fee-on-transfer token
    /// that delivers less would otherwise credit a depositor with tokens the vault does not hold,
    /// and the solvency invariant would be broken by the first deposit. This is the same Code4rena
    /// Cudos lesson FeeCollector applies, and it matters more here because the number it corrupts is
    /// a custody balance.
    function deposit(uint256 amount, uint256 maxNotional_) external nonReentrant {
        _deposit(msg.sender, amount, maxNotional_);
    }

    /// @notice Deposit using an EIP-2612 signature instead of a prior approval, task 9.4.
    ///
    /// One transaction that grants and consumes the allowance atomically, so nothing is left
    /// standing afterwards. The value permitted is exactly `amount`: this path exists to remove a
    /// click, and removing it by asking for an unbounded allowance would be trading the user's
    /// custody position for a friction metric.
    ///
    /// The permit call is NOT wrapped in try/catch. A front-runner can submit the same signature
    /// first, which would make this permit revert on the consumed nonce even though the allowance
    /// the user wanted now exists. Swallowing that is the usual advice, and it is rejected here: a
    /// deposit that silently proceeds on an allowance the caller did not establish in this
    /// transaction is a deposit whose preconditions nobody checked. A revert is recoverable, the UI
    /// names it, and the user presses the button again against the allowance that now exists.
    function depositWithPermit(
        uint256 amount,
        uint256 maxNotional_,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        IERC20Permit(asset).permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(msg.sender, amount, maxNotional_);
    }

    /// @dev The single deposit implementation, shared by both entry points so they cannot drift.
    ///      Private, and every caller passes `msg.sender`, so no input reaches another depositor.
    function _deposit(address depositor, uint256 amount, uint256 maxNotional_) private {
        if (amount == 0) revert ZeroAmount();

        uint256 before = IERC20Vault(asset).balanceOf(address(this));
        if (!IERC20Vault(asset).transferFrom(depositor, address(this), amount)) {
            revert TransferFailed();
        }
        uint256 received = IERC20Vault(asset).balanceOf(address(this)) - before;
        if (received < amount) revert ShortDeposit(amount, received);

        balanceOf[depositor] += received;
        totalDeposits += received;
        maxNotional[depositor] = maxNotional_;

        emit LimitSet(depositor, maxNotional_);
        emit Deposited(depositor, received, maxNotional_, balanceOf[depositor]);
    }

    /// @notice Withdraw. Callable ONLY by the depositor, for their own balance.
    ///
    /// DELIBERATELY NOT GATED ON `paused`. A depositor can withdraw in full while paused, and that
    /// is the point: pause protects a user from their agent, and a pause that also locked the exit
    /// would be the trap the audit guidance warns about. Task 8.4 proves this independence.
    ///
    /// Checks-effects-interactions: the balance is reduced before the token moves, so a reentrant
    /// call through the token's transfer hook finds the balance already spent.
    function withdraw(uint256 amount) external nonReentrant {
        _withdraw(msg.sender, amount);
    }

    /// @notice Withdraw everything currently withdrawable. Exists because "get me out" should not
    ///         require a user to first read a balance and type it back in, which is a step at which
    ///         a panicking user makes a mistake.
    function withdrawAll() external nonReentrant returns (uint256 amount) {
        amount = withdrawable(msg.sender);
        _withdraw(msg.sender, amount);
    }

    /// @dev The single withdrawal implementation. INTERNAL, and reached only through the two entry
    ///      points above, both of which pass `msg.sender` as the depositor. There is deliberately no
    ///      external function taking a depositor address: an earlier draft had one, restricted to
    ///      self-calls so `withdrawAll` could reuse it, and that is an externally reachable function
    ///      whose safety rests on one `msg.sender == address(this)` line. An internal function has no
    ///      such surface to get wrong. `amount` is always the caller's own, so no input reaches
    ///      another depositor's balance.
    ///
    ///      `nonReentrant` sits on the entry points rather than here, because a modifier on an
    ///      internal function called from an already-guarded external one would revert on the
    ///      transient flag it set itself.
    function _withdraw(address depositor, uint256 amount) private {
        if (amount == 0) revert ZeroAmount();
        uint256 available = withdrawable(depositor);
        if (amount > available) revert InsufficientBalance(amount, available);

        // EFFECTS
        balanceOf[depositor] -= amount;
        totalDeposits -= amount;
        emit Withdrawn(depositor, amount, balanceOf[depositor]);

        // INTERACTIONS
        if (!IERC20Vault(asset).transfer(depositor, amount)) revert TransferFailed();
    }

    /// @notice Stop the agent acting on YOUR funds. Only you can set this, and only for yourself.
    function setPaused(bool paused_) external {
        paused[msg.sender] = paused_;
        emit PauseSet(msg.sender, paused_);
    }

    /// @notice Change your own per-action notional ceiling.
    function setMaxNotional(uint256 maxNotional_) external {
        maxNotional[msg.sender] = maxNotional_;
        emit LimitSet(msg.sender, maxNotional_);
    }

    // ------------------------------------------------------------------------- agent operations

    /// @notice Commit a depositor's funds to one agent action.
    ///
    /// This is the ONLY function by which the agent moves anything, and it can send only to the
    /// immutable `tradeTarget`. The agent cannot name a destination, so there is no input under
    /// which this becomes a withdrawal to an attacker address.
    ///
    /// Three independent gates, in order: the caller must be the agent, the depositor must not be
    /// paused, and the notional must be within that depositor's own ceiling.
    function openTrade(address depositor, uint256 notional) external onlyAgent nonReentrant {
        if (notional == 0) revert ZeroAmount();
        if (paused[depositor]) revert DepositorPaused(depositor);
        if (notional > maxNotional[depositor]) {
            revert ExceedsUserLimit(notional, maxNotional[depositor]);
        }
        uint256 free = withdrawable(depositor);
        if (notional > free) revert InsufficientBalance(notional, free);

        committed[depositor] += notional;
        totalCommitted += notional;
        emit TradeOpened(depositor, notional);

        if (!IERC20Vault(asset).transfer(tradeTarget, notional)) revert TransferFailed();
    }

    /// @notice Return funds from a completed action and settle the depositor's balance.
    ///
    /// The amount credited is the measured delta, so a trade target that returns less than it claims
    /// cannot inflate a depositor's balance. Profit and loss both land on the depositor whose funds
    /// were traded, which is what makes per-user limits mean something.
    function closeTrade(address depositor, uint256 notional, uint256 returned)
        external
        onlyAgent
        nonReentrant
    {
        if (committed[depositor] < notional) revert NothingCommitted();

        uint256 before = IERC20Vault(asset).balanceOf(address(this));
        if (returned > 0) {
            if (!IERC20Vault(asset).transferFrom(msg.sender, address(this), returned)) {
                revert TransferFailed();
            }
        }
        uint256 received = IERC20Vault(asset).balanceOf(address(this)) - before;

        committed[depositor] -= notional;
        totalCommitted -= notional;

        // The depositor's balance is reduced by what left and increased by what came back.
        balanceOf[depositor] = balanceOf[depositor] - notional + received;
        totalDeposits = totalDeposits - notional + received;

        emit TradeClosed(depositor, notional, received);
    }

    // ---------------------------------------------------------------------------- owner operations

    /// @notice Rotate the agent. This is the ONLY owner power, and it deliberately does not reach
    ///         any depositor's funds: a new agent inherits the same three gates as the old one.
    function setAgent(address agent_) external onlyOwner {
        if (agent_ == address(0)) revert ZeroAddress();
        agent = agent_;
        emit AgentSet(agent_);
    }

    // ------------------------------------------------------------------------------------- views

    /// @notice What a depositor can take out right now: their balance less anything in flight.
    function withdrawable(address depositor) public view returns (uint256) {
        uint256 bal = balanceOf[depositor];
        uint256 out = committed[depositor];
        return bal > out ? bal - out : 0;
    }

    /// @notice The solvency check, readable by anyone at any time. The vault must hold at least what
    ///         it says it owes, less whatever is legitimately out with the trade target.
    ///
    /// `totalCommitted` is maintained as a running sum in `openTrade` and `closeTrade`. A first draft
    /// declared the field and never wrote to it, so this function would have returned false for any
    /// vault with an open trade while the vault was perfectly solvent. A solvency check that reads
    /// wrong is worse than none, because it is the number an operator would point at.
    function isSolvent() external view returns (bool) {
        return IERC20Vault(asset).balanceOf(address(this)) + totalCommitted >= totalDeposits;
    }
}
