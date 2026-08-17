// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {AgentVault} from "../src/AgentVault.sol";

/// Task 9.4 / ADR-017: EIP-2612 permit, so a cold activation is three interactions rather than four.
///
/// THINKING: #66 red teaming (a signature scheme is only as good as what it REFUSES), #29
/// margin-of-safety, #22 inversion (do not ask whether a valid signature works, ask what an invalid
/// one does).
///
/// The happy path is one test. The other nine are the ones that matter, because a permit
/// implementation that accepts a valid signature and ALSO accepts a replayed, expired, wrong-spender,
/// wrong-amount, wrong-chain or forged one is worse than no permit at all: it is an approval
/// primitive an attacker can drive.
contract PermitTest is Test {
    MockERC20 token;
    AgentVault vault;

    uint256 constant OWNER_KEY = 0xA11CE;
    address owner;
    address spender = address(0x59E0D);
    address tradeTarget = address(0x7A46);

    uint256 constant AMOUNT = 25 ether;

    function setUp() public {
        owner = vm.addr(OWNER_KEY);
        token = new MockERC20("Test Quote", "tQUOTE");
        vault = new AgentVault(address(token), tradeTarget);
        vault.setAgent(address(0xA6E7));
        token.mint(owner, 1_000 ether);
    }

    /// Build a signature the way a wallet would: EIP-712 typed data over the permit struct.
    function _sign(
        uint256 key,
        address owner_,
        address spender_,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(token.PERMIT_TYPEHASH(), owner_, spender_, value, nonce, deadline)
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(key, digest);
    }

    // ------------------------------------------------------------------------------ happy path

    function test_permitGrantsTheAllowanceWithoutATransactionFromTheOwner() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _sign(OWNER_KEY, owner, spender, AMOUNT, token.nonces(owner), deadline);

        assertEq(token.allowance(owner, spender), 0);

        // Note the caller: NOT the owner. That is the entire point. The owner signed offchain and
        // never sent a transaction, which is the click this removes.
        vm.prank(address(0xBEEF));
        token.permit(owner, spender, AMOUNT, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), AMOUNT);
        assertEq(token.nonces(owner), 1, "the nonce advanced");
    }

    /// The task's actual claim: deposit and activate in ONE transaction from a cold allowance.
    function test_depositWithPermitActivatesFromAColdAllowanceInOneTransaction() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _sign(OWNER_KEY, owner, address(vault), AMOUNT, token.nonces(owner), deadline);

        assertEq(token.allowance(owner, address(vault)), 0, "genuinely cold: no prior allowance");

        vm.prank(owner);
        vault.depositWithPermit(AMOUNT, AMOUNT, deadline, v, r, s);

        assertEq(vault.balanceOf(owner), AMOUNT);
        assertEq(vault.maxNotional(owner), AMOUNT);
        assertEq(token.balanceOf(address(vault)), AMOUNT);
        // Nothing is left standing. The allowance was granted and consumed in the same transaction,
        // which is why this asks for exactly `amount` rather than type(uint256).max.
        assertEq(token.allowance(owner, address(vault)), 0, "no residual allowance");
    }

    // ------------------------------------------------------------------------ what it must REFUSE

    function test_aReplayedSignatureIsRefused() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _sign(OWNER_KEY, owner, spender, AMOUNT, token.nonces(owner), deadline);

        token.permit(owner, spender, AMOUNT, deadline, v, r, s);

        // The nonce has advanced, so the same bytes now recover to a different address.
        vm.expectRevert(MockERC20.InvalidSignature.selector);
        token.permit(owner, spender, AMOUNT, deadline, v, r, s);
    }

    function test_anExpiredSignatureIsRefused() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _sign(OWNER_KEY, owner, spender, AMOUNT, token.nonces(owner), deadline);

        vm.warp(deadline + 1);

        vm.expectRevert(
            abi.encodeWithSelector(MockERC20.PermitExpired.selector, deadline, block.timestamp)
        );
        token.permit(owner, spender, AMOUNT, deadline, v, r, s);
        assertEq(token.allowance(owner, spender), 0);
    }

    /// A signature is bound to its spender. Otherwise anyone observing it in the mempool could
    /// redirect the allowance to themselves.
    function test_aSignatureCannotBeRedirectedToADifferentSpender() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _sign(OWNER_KEY, owner, spender, AMOUNT, token.nonces(owner), deadline);

        vm.expectRevert(MockERC20.InvalidSignature.selector);
        token.permit(owner, address(0xBAD), AMOUNT, deadline, v, r, s);
    }

    function test_aSignatureCannotBeInflatedToALargerAmount() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _sign(OWNER_KEY, owner, spender, AMOUNT, token.nonces(owner), deadline);

        vm.expectRevert(MockERC20.InvalidSignature.selector);
        token.permit(owner, spender, AMOUNT * 1000, deadline, v, r, s);
    }

    function test_aSignatureFromTheWrongKeyIsRefused() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _sign(0xBADBAD, owner, spender, AMOUNT, token.nonces(owner), deadline);

        vm.expectRevert(MockERC20.InvalidSignature.selector);
        token.permit(owner, spender, AMOUNT, deadline, v, r, s);
    }

    /// THE address(0) CASE. `ecrecover` returns address(0) for a malformed signature. Without an
    /// explicit check, a garbage signature naming address(0) as owner would succeed and approve on
    /// its behalf. This is the classic ecrecover footgun and it is worth its own test.
    function test_aGarbageSignatureCannotApproveOnBehalfOfAddressZero() public {
        uint256 deadline = block.timestamp + 1 hours;
        vm.expectRevert(MockERC20.InvalidSignature.selector);
        token.permit(address(0), spender, AMOUNT, deadline, 27, bytes32(uint256(1)), bytes32(uint256(2)));
        assertEq(token.allowance(address(0), spender), 0);
    }

    /// The domain separator binds a signature to THIS chain. A testnet signature must not be
    /// replayable on mainnet in Phase 12, which is why the separator is recomputed per call rather
    /// than cached at construction with the deployment-time chain id frozen into it.
    function test_aSignatureFromAnotherChainIsRefused() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 separatorHere = token.DOMAIN_SEPARATOR();

        vm.chainId(196);
        bytes32 separatorThere = token.DOMAIN_SEPARATOR();
        assertTrue(separatorHere != separatorThere, "the separator must track the chain id");

        // Sign under chain 196, then go back to 1952 and try to use it.
        (uint8 v, bytes32 r, bytes32 s) =
            _sign(OWNER_KEY, owner, spender, AMOUNT, token.nonces(owner), deadline);
        vm.chainId(1952);

        vm.expectRevert(MockERC20.InvalidSignature.selector);
        token.permit(owner, spender, AMOUNT, deadline, v, r, s);
    }

    /// A front-runner submitting the user's permit first consumes the nonce, so the user's own
    /// depositWithPermit reverts. ADR-017 records why this is NOT swallowed with a try/catch: a
    /// deposit that proceeds on an allowance nobody checked in this transaction has unverified
    /// preconditions. The revert is recoverable and the UI names it.
    function test_aFrontRunPermitMakesTheDepositRevertRatherThanProceedBlindly() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _sign(OWNER_KEY, owner, address(vault), AMOUNT, token.nonces(owner), deadline);

        // Somebody else lands the permit first.
        vm.prank(address(0xF00D));
        token.permit(owner, address(vault), AMOUNT, deadline, v, r, s);
        assertEq(token.allowance(owner, address(vault)), AMOUNT, "the allowance now exists");

        vm.prank(owner);
        vm.expectRevert(MockERC20.InvalidSignature.selector);
        vault.depositWithPermit(AMOUNT, AMOUNT, deadline, v, r, s);

        // And the recovery the UI offers works: the plain deposit path uses the allowance that the
        // front-runner established.
        vm.prank(owner);
        vault.deposit(AMOUNT, AMOUNT);
        assertEq(vault.balanceOf(owner), AMOUNT);
    }

    /// The two entry points must agree, since they share `_deposit`. If they ever diverge, one of
    /// them is wrong and this catches it.
    function test_bothDepositPathsProduceIdenticalState() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            _sign(OWNER_KEY, owner, address(vault), AMOUNT, token.nonces(owner), deadline);

        vm.prank(owner);
        vault.depositWithPermit(AMOUNT, AMOUNT, deadline, v, r, s);
        uint256 balA = vault.balanceOf(owner);
        uint256 limA = vault.maxNotional(owner);

        address other = address(0x0B12);
        token.mint(other, AMOUNT);
        vm.prank(other);
        token.approve(address(vault), AMOUNT);
        vm.prank(other);
        vault.deposit(AMOUNT, AMOUNT);

        assertEq(vault.balanceOf(other), balA);
        assertEq(vault.maxNotional(other), limA);
    }
}
