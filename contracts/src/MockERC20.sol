// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title MockERC20
/// @notice TEST TOKEN. Not a real asset. Deployed on X Layer testnet so the
///         venue can perform genuine transfers and genuine escrow, because a
///         fill that does not move tokens is not a fill.
///         Written by hand rather than pulled from OpenZeppelin to avoid a
///         network dependency during install. Minimal on purpose.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance(uint256 have, uint256 need);
    error InsufficientAllowance(uint256 have, uint256 need);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /// @notice Open mint. This is a test token on a testnet; gating it would add
    ///         friction without adding safety. Stated plainly rather than dressed
    ///         up as a faucet.
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance(allowed, amount);
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        uint256 bal = balanceOf[from];
        if (bal < amount) revert InsufficientBalance(bal, amount);
        balanceOf[from] = bal - amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    // ------------------------------------------------------------------ EIP-2612 permit

    /// @notice Per-owner nonce, so a signature cannot be replayed.
    mapping(address => uint256) public nonces;

    /// @dev keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /// @dev keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 private constant DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    error PermitExpired(uint256 deadline, uint256 nowTs);
    error InvalidSignature();

    /// @notice EIP-712 domain separator, computed on every call rather than cached at construction.
    ///
    /// Caching it is the usual optimisation and it is WRONG for a contract that might be deployed to
    /// more than one chain from the same source: a cached separator freezes the chain id at
    /// construction, and a fork would let a signature from one chain be replayed on the other. This
    /// project deploys to testnet 1952 now and mainnet 196 in Phase 12, so the two must not share a
    /// valid signature. Recomputing costs a few hundred gas on a path that already costs an SSTORE.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Approve by signature instead of by transaction, EIP-2612.
    ///
    /// This is what makes a cold-start activation three interactions rather than four: the approval
    /// stops being a transaction the user must confirm and becomes a signature they sign, with no
    /// gas and no block.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // forge-lint flags block.timestamp in a comparison, and it is correct to in general. Here
        // it is what EIP-2612 specifies, and the manipulation it warns about is a validator moving
        // the timestamp by seconds against a deadline the UI sets minutes out. The deadline exists
        // to bound how long a signature stays valid, not to order events, so second-level drift
        // cannot change an outcome.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline) revert PermitExpired(deadline, block.timestamp);

        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        address recovered = ecrecover(digest, v, r, s);
        // address(0) is what ecrecover returns for a malformed signature, so checking it is not
        // paranoia: without this, a garbage signature would "recover" to address(0) and, if owner
        // were also address(0), approve on its behalf.
        if (recovered == address(0) || recovered != owner) revert InvalidSignature();

        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }
}
