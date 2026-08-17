# Phase 5 gate: the terminal shows every capability v1 proved

Four views, driven by the tab bar or the digit keys 1 to 4. Every panel reads the agent's own output
files and computes nothing that a script has not already written.

## Measured

| metric | value | task |
|---|---|---|
| unexplained numeric literals in render paths | **0** of 329 | 5.2 |
| metrics counters recomputable by one command | **all**, panel renders `data/metrics.json` | 5.1 |
| journal feed at 500 rows | **28 mounted**, 34.8 ms median two-frame latency over a 40-jump burst | 5.3 |
| comparator states captured live on chain | **3** (healthy, paused, diverged) | 5.4 |
| comparator gate assertions | **5 of 5**, including the crypto-approved-everywhere control | 5.5 |
| learning rows stating their own sample size | **all**, threshold 30 named on screen | 5.6 |
| one-candidate journal rows flagged | **43 of 43** | 5.7 |
| characters below WCAG AA | **0.00%**, worst ratio 8.28:1 | readability |
| clipping containers / collapsed columns | **0 / 0** at 1280x720 and 640x600 | layout |

## The RWA comparator is the money screen, and its healthy state is the load-bearing one

The same order, `Buy 2.000000 base at 1.000000`, judged against a crypto market and an RWA market, in
three states produced by moving the real vault on chain 1952:

| state | crypto | RWA | cause named by the engine |
|---|---|---|---|
| healthy | APPROVED | **APPROVED** | none, and that is the point |
| issuer paused | APPROVED | REFUSED | `RwaIssuerPaused` |
| oracle diverged | APPROVED | REFUSED | `RwaOracleMarketDivergence { got_bps: 1000, limit_bps: 300 }` |

The gate asserts five properties, and the one that matters most is the **control**: the crypto market
approved in every state. Without it, a difference between the two columns could come from anything.
With it, the only thing that changed is the instrument.

TASKS.md names showing only the refusing states as this task's fake win, and it is right: an RWA layer
that refuses in every state is a global brake, not a risk control that reads the instrument. The
healthy capture is what distinguishes them, so it is a required artifact and the gate fails without it.

## Four defects this phase found in itself

1. **Positional address parsing.** The comparator script took the 6th and 7th address out of a
   human-written markdown table, which are BatchExecutor and a truncated market id. Every setup
   transaction went to the wrong contract and returned nothing, the oracle stayed three days stale, and
   **all three states refused** including the healthy one. The gate caught it: `healthy shows both
   approving: False`. Addresses are now looked up by name.
2. **Two duplicated display thresholds.** The utilisation bar had its own copy of 70 and 90 while
   `UTILISATION.WARN_PCT` and `DANGER_PCT` already existed. Found by 5.2's literal audit.
3. **A chain id typed into a render path.** `chain?.chainId === 1952` made the UI an authority on
   which chain is correct. It now compares the loaded manifest against a named constant, which is a
   different thing from knowing the answer.
4. **Buttons with no pointer cursor.** A native `<button>` defaults to `cursor: default`, measured on
   the view tabs while the anchor beside them correctly read `pointer`. Every tab and row control was
   hittable and gave no sign of it.

## What is deliberately not claimed

**PNG artifacts.** TASKS.md names `.png` files for 5.1, 5.3, 5.4 and 5.6. The captures here are DOM
measurements and text captures instead, because this environment's browser pane composites at a
smaller surface than the layout viewport, so a screenshot would show a correct 1600x900 layout rendered
into roughly 630x350 and would misrepresent the thing it claims to document. The DOM measurements are
strictly stronger for every assertion the tasks actually make: exact verdict strings, exact mounted
row counts, exact contrast ratios. Stated as a deviation rather than filed as a pass.

**Learning at n=2.** The learning panel leads with the sample size, labels anything below 30 settled
outcomes as too small to read as a hit rate, and states that flat outcomes are discarded rather than
scored as correct. `docs/decisions/ADR-011-river-role.md` records why river stayed a benchmark: its
margin over the majority baseline is **two predictions out of 79**, and the target is behaviour rather
than profit because the journal carries no realized PnL until 8.5.
