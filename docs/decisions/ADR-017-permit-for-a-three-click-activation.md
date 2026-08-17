# ADR-017: ERC-2612 permit, so activation is three interactions and not four

Status: ACCEPTED, 2026-08-15. Driven by task 9.4.

## Context

Task 9.4's PASS condition is **three or fewer clicks** from a connected wallet to a running agent,
"counting every click including wallet confirmations that the app triggers". Its named fake win is
"counting only in-app clicks and ignoring wallet confirmations".

The cold-user path today is FOUR interactions:

| # | interaction | why |
|---|---|---|
| 1 | click Approve | the vault cannot pull tokens without an allowance |
| 2 | confirm the approval in the wallet | it is a transaction |
| 3 | click Deposit and activate | the actual deposit |
| 4 | confirm the deposit in the wallet | it is a transaction |

It measured as ONE click during 9.3's verification, and that measurement was not usable. The deployer
already held a 1e24 allowance granted during Phase 7, so the Approve step never rendered. That is not
a cold user. Reporting one click on that basis would have been the fake win with extra steps: the
number would have been true of the account I happened to test with and false of every real first
visitor.

## Options considered

**1. Count only in-app clicks.** This is the named fake win, verbatim. Rejected.

**2. Pre-approve in a fixture and call the user cold.** The same fake win wearing a setup script.
Rejected.

**3. Ask for an unbounded allowance once and call the second visit three clicks.** Rejected twice
over: it is still four for the first user, which is the user the task is about, and an infinite
allowance to a contract is a standing risk a careful user should refuse. Optimising a friction metric
by asking users to take more custody risk is the wrong trade.

**4. ERC-2612 permit.** A signature replaces the approval transaction. The path becomes:

| # | interaction |
|---|---|
| 1 | click Deposit and activate |
| 2 | sign the permit (a signature, not a transaction: no gas, no block) |
| 3 | confirm the deposit transaction |

Three, for a genuinely cold user with no prior allowance. **Chosen.**

## Decision

Add EIP-2612 `permit` to `MockERC20`, and `depositWithPermit` to `AgentVault`.

`depositWithPermit` calls `permit` and then performs the ordinary deposit in one transaction, so the
allowance is granted and consumed atomically. The allowance requested is exactly the deposit amount,
not `type(uint256).max`, so nothing is left standing afterwards. That is a better custody posture
than option 3 as well as a shorter path, which is the argument for doing this rather than merely the
argument for it being fewer clicks.

The existing `deposit(uint256,uint256)` stays. A wallet without permit support, and any user who
prefers a plain approval, still has a working path; the UI falls back to it when the token reports no
permit support. Removing the two-step path to force the one-step path would trade a real capability
for a metric.

## Consequences

- `MockERC20` and `AgentVault` both change, so BOTH are redeployed and every Phase 8 gate that covers
  them is re-run. A Phase 9 convenience is not allowed to silently invalidate a Phase 8 proof.
- The permit signature is EIP-712 typed data, so the injected test provider must implement
  `eth_signTypedData_v4`, which it currently refuses. It will sign with the same key via the test
  signer, keeping signing in `cast` per ADR-008.
- Replay is prevented by a per-owner `nonces` mapping and a deadline, both part of the standard. The
  domain separator binds the signature to this chain id and this token address, so a signature from
  testnet cannot be replayed on mainnet in Phase 12.
- `MockERC20` is a test token. Writing `permit` by hand rather than importing OpenZeppelin keeps the
  no-network-dependency property the file already has, and the implementation is checked against the
  spec's own test vector rather than trusted.
