# ADR-016: verifying the connect flow without a browser extension

Status: ACCEPTED, 2026-08-15. Supersedes nothing. Revisit when task 9.0 completes.

## Context

Task 9.0 is marked **USER HANDLES** and **BLOCKING**: install OKX Wallet or MetaMask, add chain 1952,
hold testnet OKB. It has been raised with the user and is not yet done. The task's own text says
"9.1 through 9.10 can be built but only 9.6 can be verified end to end", so the plan anticipates
building ahead of it.

The standing instruction is to continue and to decide everything that is not a USER HANDLES task or a
hard external blocker. 9.0 has been surfaced once; re-raising it per subtask would be noise. The
question this ADR answers is what "verified" is allowed to mean for 9.1 through 9.10 in the meantime.

## The trap

Task 9.1's named fake win is **"a Connect button that sets local state without touching a
provider"**, and its counter is that the evidence must record the address returned by
`eth_requestAccounts` and the chain id. The obvious shortcut, stubbing `window.ethereum` with an
object that returns a hardcoded address, is exactly that fake win with extra steps. It would make
every gate in this phase green and prove nothing.

## Decision

Verify against a **real, key-backed EIP-1193 provider** injected into the Browser pane for the
duration of a gate run, and label it precisely everywhere it is used.

What makes this a real provider rather than a mock:

- It holds an actual X Layer testnet private key and derives its address from that key.
- `eth_requestAccounts` returns that derived address, not a literal.
- `eth_chainId` is answered by querying `https://testrpc.xlayer.tech`, not by returning `0x7a0`.
- `eth_sendTransaction` signs with the key and broadcasts. Transactions land in real blocks with real
  hashes that resolve on the explorer.

The application code under test cannot distinguish it from an extension, because the interface is the
same interface. What it is NOT is the extension itself, and the difference matters in two specific
places, both stated rather than glossed:

1. **User-facing confirmation UX.** An extension shows a popup the user must approve. The provider
   here approves programmatically. Task 9.4 counts clicks *including wallet confirmations*, so its
   count is computed as in-app clicks plus a stated constant for the confirmations the app triggers,
   and the constant is listed per click rather than folded into a total.
2. **Rejection paths.** Task 9.8 requires a rejected signature to be recoverable. The provider
   implements a rejection mode that returns EIP-1193 error code 4001, which is what an extension
   returns when a user clicks Reject, so the application path is genuinely exercised.

## Why not the alternatives

**Wait for 9.0.** Rejected: it stalls the highest-value phase in the plan on an action outside this
session, and the plan explicitly says the work can proceed.

**Stub `window.ethereum` with fixed values.** Rejected: it is the named fake win.

**Use a wallet-connection library and trust its tests.** Considered under R-SEARCH-3. Rejected because
the thing being verified IS the connection code; a library's own test suite says nothing about whether
this application connects, and adding a dependency does not produce the address-and-chain-id evidence
the task asks for.

## Consequences

- Every Phase 9 evidence file carries an explicit line naming which provider produced it.
- The Phase 9 gate report states, in its own section, that extension verification is outstanding, so
  no reader can mistake these passes for extension passes.
- When 9.0 lands, the same gates re-run unchanged against the extension. Nothing in the application
  needs to change, which is itself the argument that the abstraction is honest: if a gate passes here
  and fails there, the difference is in the extension's behaviour and worth finding.
- Task 9.6, the Run Full Demo button, requires no wallet at all and is verified with no provider
  involved, exactly as the plan says.
