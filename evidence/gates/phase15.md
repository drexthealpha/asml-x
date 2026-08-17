# Phase 15 gate report: coordination residue

Run 2026-08-16 19:01:08 UTC. Verdict: **PASS**

## 15.1, adversarial audit of the deployed fee and vault surfaces

Nine hostile calls executed against the DEPLOYED bytecode with a hostile `msg.sender`, all
refused with the exact expected error selector, and three negative controls executed as the
same attacker all succeeding with decoded values: fee quote 4900, solvency true, withdrawable
25000000000000000000.

Two things this run got right only after getting them wrong, both recorded in the script:

1. **Matching on the error NAME failed every case while the controls passed.** An X Layer node
   returns custom errors as raw calldata with no name in the response. That pattern, all
   probes failing and all controls passing, means the match is wrong rather than the contract.
   Now matched on the selector computed by `cast sig` at run time, which is the stronger
   claim: "it reverted" and "it reverted for the reason I said" are different findings.
2. **The controls printed raw 32-byte words truncated to 40 characters**, which cuts off the
   last word. A solvency check reading `false` would have displayed identically to `true`.
   Now called with typed return signatures so the row shows a decoded value.

## 15.2, protocol version and compatibility note

`docs/COORDINATION-PROTOCOL.md` at version 1.0.0, GENERATED from a live probe in the same run
that writes it. Five endpoints exercised end to end including a full quote and accept round
trip, and four refusal codes captured: 401 without a key, 404 on an unknown quote id, 400 on a
numeric `size_micro`, 404 on an unknown endpoint.

The document states what the API is NOT, so nobody integrates against a promise never made: it
is not a venue, not multi-market, not authenticated per identity, and its fee is quoted rather
than charged.

## Reproduce

```
bash scripts/178-adversarial-fee-vault.sh
bash scripts/179-protocol-version.sh
```
