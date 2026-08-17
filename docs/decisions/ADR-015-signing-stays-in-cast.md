# ADR-015: signing stays in the cast subprocess

Task 6.6. Status: ACCEPTED. Date: 2026-08-13.

Numbered 015 rather than 014: TASKS.md 6.6 names ADR-014, but 014 was taken by the external
settlement decision earlier in this phase. Recorded rather than renumbered, so the reference in
TASKS.md still resolves to a real document via this note.

THINKING: #30 trade-off (in-process signing buys latency and costs a dependency plus a key in more
address space), #27 opportunity-cost (what does this displace with days left), #23 second-order (a
signer inside the runtime changes what a runtime compromise means).

## The debt this addresses

ADR-008 recorded two disclosed limitations: no dynamic ABI, and signing through a `cast` subprocess.
Task 1.12 proved alloy works here, returning byte-identical results to the hand-rolled client for the
same call at the same block, so migrating is genuinely available rather than blocked.

## Decision

**Keep the `cast` subprocess.** Do not migrate signing in-process.

## The measurement behind it

`bash scripts/98-signing-latency.sh`, three runs each:

| stage | measured | share of a submission |
|---|---|---|
| keystore decrypt (scrypt) | 0.072s, 0.089s warm (1.514s cold) | ~0.3% |
| `cast` process spawn | 0.022s, 0.023s, 0.024s | ~0.1% |
| one chain round trip | 0.657s to 5.396s | varies |
| **read-to-landing, 39 real submissions** | **22 to 30 blocks, median 25** | **the whole thing** |

The read-to-landing figure is not a microbenchmark: it is every submitted decision in the journal
checked against its own receipt (`evidence/phase4/seam-test.md`), min 22 blocks, median 25, max 30, at
roughly 1.0s per block.

So the subprocess costs about **0.11 seconds of a 22 to 30 second path, roughly 0.4%**. Removing it
would leave 99.6% of the latency exactly where it is, because the latency is the chain: gas estimation,
submission, and waiting for inclusion.

## What migrating would cost

1. **The private key moves into the runtime's address space.** Today `cast` holds the decrypted key
   for the life of one subprocess and exits. In-process, it lives as long as the agent does, in the
   same process as the coordination handoff reader and the journal writer. That is a strictly larger
   blast radius for any memory-disclosure bug, in exchange for 0.4%.
2. **A dependency on the signing path.** alloy is already a workspace dependency for reads, so this is
   not a new crate, but it becomes load-bearing for spending rather than for querying.
3. **Re-verification.** Every transaction this project has produced went through `cast`. Changing the
   signer days before a deadline means the 39 verified submissions no longer exercise the code path
   that would ship.

## What keeping it costs, stated plainly

- ~0.11s per submission, which is 0.4% of the observed latency.
- A process spawn per transaction, so submission rate is bounded by fork/exec rather than by the
  chain. At this volume that bound is nowhere near binding.
- `cast` must be on PATH, which is already true for every script in this repo and is checked by the
  toolchain gate.

## When this decision should be revisited

If submission volume rises to where a fork per transaction matters, or if the agent needs to sign
something `cast` cannot express. Neither is true now, and the first is measurable: the crossover is
roughly where 0.11s per submission stops being 0.4% of the path, which means sub-second inclusion.

## The other half of ADR-008's debt

**Dynamic ABI is still not implemented,** and this ADR does not close it. The hand-rolled client
encodes calls with a fixed selector-and-word scheme, which is why every contract call in this repo is
written out by hand. alloy's `sol!` macro would replace that, and it is a real improvement to code
quality with no effect on what the product can prove. Left undone deliberately, and named here rather
than left implied.
