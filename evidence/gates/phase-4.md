# Phase 4 gate: the AI decision layer is live and agent-driven

Captured 9 Aug 2026. Chain 1952. The spine is no longer script-driven.

## What the agent now does, end to end

Per cycle: read the real order book over JSON-RPC, compute signals with confidence
intervals and chain-time staleness, form a thesis from those numbers, generate a
candidate set from the live book, score every candidate on four competing terms,
put EVERY action candidate through the risk gate, choose the highest-scoring
permitted candidate, submit it atomically through BatchExecutor, and journal all of
it with the rejected alternatives.

## Live agent-driven transactions

Three real transactions submitted by the runtime, not by a script:

| cycle | block | decision | tx |
|---|---|---|---|
| 0 | 37813906 | take order 3, Sell 1.500000 base at 1.900000 | `0xbed1a412229db6557645a893e3465e821d5622872c8ebef8cffce3eaede80a5d` |
| 1 | 37813921 | take order 4, Sell 1.000000 base at 1.800000 | `0x03609244f14d3bd14db73e46f0205ef595a9214d7af30399b090748f5ccd965f` |
| 2 | 37813938 | take order 3, Sell 0.750000 base at 1.900000 | `0x34bf908d4fc3e23cb1be655bd47a32c6b11e4945827fcad4552ecdbd7fd7ccab` |

Guard exposure moved 4.0e18 to 10.075e18, and `gross() == sumOfParts()` throughout.

The agent adapted as its own fills changed the book: measured depth imbalance went
3750 to 5172 to 6296 bps, and it chose a different order and a different size each
cycle. That is the decision responding to state, which is the claim.

## The candidate set is a real search

Eleven candidates per cycle, generated from the live book rather than a fixed menu.
From the last journal entry:

| candidate | score | why not chosen |
|---|---|---|
| take order 3 Sell 0.750000 at 1.900000 | 93480 | CHOSEN |
| take order 4 Sell 0.500000 at 1.800000 | 59040 | lower score |
| take order 3 Sell 0.375000 at 1.900000 | 49412 | lower score |
| take order 4 Sell 0.250000 at 1.800000 | 31208 | lower score |
| hold | 0 | lower score |

`assert_real_search` refuses to journal a cycle that evaluated one candidate, and a
test asserts the count is never 1.

## Two real bugs found and fixed, both of which looked like correct behaviour

1. **Unit scale.** The chain speaks 18 decimals, the risk engine speaks 6. Raw
   values were fed straight across, making every notional read about 1e24 times too
   large, so the risk engine refused 10 of 11 candidates every cycle. On screen this
   looked exactly like a conservative agent working properly. Fixed with a single
   `WEI_PER_MICRO` boundary conversion plus regression tests.
2. **Backwards taker economics.** The scorer credited a taker with a fraction of the
   observed spread. A taker PAYS the spread; the maker who posted the order earns
   it. With that error the agent held on every cycle, which again looked like
   sensible caution. Rewritten: a taker's edge is directional, derived from damped
   depth imbalance scaled by that signal's own confidence, with the half-spread
   charged as a crossing cost. After the fix the agent sells into bids when the book
   is ask-heavy, which is the correct read.

Neither bug would have been caught by reading passing output. Both changed the
agent from "does nothing, looks careful" to "acts for a stated reason".

## Baseline comparison, reported as observed

Window pre-declared in `evidence/baseline-comparison/declared-window.md` before
either mode ran, from block 37814247, four cycles each.

Result: in that window the engine chose ONE distinct action, the same count as the
naive baseline. The engine did not show more variety than the baseline here.

Why, stated rather than explained away: in observe mode neither run submits, so the
book is static, and identical inputs produce identical decisions. Determinism is a
property this project deliberately proved, so a static book yielding one repeated
decision is the engine working correctly, not failing. Variety appears when state
changes, which is visible in the run-mode sequence above where the agent's own fills
moved the book.

The honest conclusion is that distinct-action-count is a poor metric on a static
book. A better comparison needs a moving book, and the run-mode evidence is the
stronger artifact. The unflattering number is kept here rather than replaced,
because the first version of this script compared every journal entry ever written,
which inflated the engine's variety to 5 distinct actions against the baseline's 1.
Scoping it to the declared window removed that flattery.

## What is NOT claimed

- No realized PnL. Fills are not marked to a later price, so nothing here supports
  a profitability claim.
- Four cycles per mode is not a performance sample.
- The venue is self-deployed and thin, so adverse selection, the main real cost of
  taking liquidity, is not represented.
- The LLM interpretation role from the plan is not wired yet. The thesis text is
  generated from the signal numbers by ordinary code. That is stated plainly because
  an LLM narrating this loop would add words, not intelligence.

## Test position

55 Rust tests green across 7 crates, including proptest properties for
"approved actions always satisfy the risk engine" and "ranking is deterministic".
