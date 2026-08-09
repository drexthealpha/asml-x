# Phase 2 gate: the spine is green

Captured 2026-08-09 07:44:20 UTC. Chain 1952, X Layer testnet.

## Definition of done, checked

| item | status | evidence |
|---|---|---|
| Risk engine, pure, no floats, no clock reads | DEMONSTRATED | crates/risk-engine, 16 tests |
| Bypassing the risk gate is a compile error | DEMONSTRATED | evidence/bypass-compile-error.txt |
| Rust mutation gate | DEMONSTRATED, 14/14 RED | evidence/mutation-risk-engine.md |
| Contracts: venue, guard, batch executor | DEMONSTRATED | docs/verified/deployments.md |
| Contract tests incl. stateful invariants | DEMONSTRATED, 26 tests | scripts/10-contracts-test.sh |
| Contract mutation gate | DEMONSTRATED, 15/15 RED | evidence/mutation-contracts.md |
| Multi-leg atomic batch live onchain | DEMONSTRATED | evidence/spine-run-01/README.md |
| Cap breach refused live, nothing moved | DEMONSTRATED | same |
| Kill switch fires live | DEMONSTRATED | same |
| De-risk still possible while killed | DEMONSTRATED | same |

## Onchain state right now

- guard.exposureOf(market) = 4000000000000000000
- guard.gross() = 4000000000000000000
- guard.sumOfParts() = 4000000000000000000
- invariant 5 holds live onchain: gross equals sum of parts

## What is NOT yet true, stated plainly

- No AI decision-making yet. Phase 4. The spine is driven by scripts, and the
  runtime does not yet decide anything. Any claim of autonomy today would be false.
- No continuous 60 minute unattended run yet (task 2.4.6). Deferred to after the
  Rust runtime drives the loop, because running a shell script for an hour proves
  nothing about the product.
- No formal verification yet. Phase 3, next.
- The venue is self-deployed. ADR-001 records why and what it costs.

## Defects found and fixed during this phase

1. Rust mutation gate found two real test gaps: an unpinned boundary on the order
   notional check, and a vacuous kill-switch property that passed because
   neutralising the branch made its precondition unreachable. Both fixed, then
   14/14.
2. Foundry invariant campaign was near-vacuous: an ungated kill in the handler
   halted the guard in roughly a third of calls, after which no cap could break
   even in principle. Fixed by restricting campaign selectors to the exposure
   paths and adding an explicit reachability test.
3. Contract mutation 14 used a sentinel string that existed before mutation, so
   it silently proved nothing. Fixed to use a post-mutation-only marker.
4. 13-live-spine.sh read exposureOf without its market argument and printed an
   empty value. Fixed here.

Item 2 is the one worth keeping in mind: two of the three most impressive-looking
artifacts in this phase, the invariant campaign and the property suite, were
initially passing for the wrong reason. Both were caught by deliberately breaking
things rather than by reading the output.
