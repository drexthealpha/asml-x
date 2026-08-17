# Phase 4 gate: the terminal UI

Seven panels reading the agent's own output files, built after the study gate opened and citing it
throughout. Every panel file names in its header comment the HypeTerminal pattern it applies, with a
`path:line` reference into `evidence/ui-study.md`.

## Measured, not asserted

| metric | value | task |
|---|---|---|
| ink coverage at 1920x1080 | **59.83%** | 4.1 |
| largest empty rectangle | **5.92%** of viewport (target 3.9%, NOT met) | 4.1 |
| numeric cells, all `tabular-nums` | **366** | 4.1 |
| live values in one header row | **11** | 4.2 |
| gradient bars (depth-bar technique) | 54 | 4.4, 4.5 |
| peak utilisation bar | **`MarketNotionalTooLarge 52.96 / 50.00 = 100%`** | 4.5 |
| contracts with a provenance badge | 7 of 7, all SELF-DEPLOYED | 4.6 |
| fabricated numbers with data absent | **0** (1 static config value) | 4.7 |
| panels naming their missing source | **7 of 7** | 4.7 |
| submitted decisions verified against chain | **39 of 39**, status 0x1 | 4.8 |
| read-to-landing drift | min 22, median 25, max 30 blocks | 4.8 |
| adversarial inputs producing a visible error | **7 of 7** | 4.9 |

Reproduce: `bash scripts/78-ui-data.sh`, build and serve `ui-v2`, then run
`scripts/measure-density.js` in the console. Then `bash scripts/86-seam-test.sh` and
`bash scripts/80-ui-redteam.sh`.

## What the panels show that a dashboard usually does not

- **The losing candidates, with their scores and why they lost.** 4.4's PASS condition is exactly
  this, and it is the anti-if-else-ladder: a panel showing only the chosen action is
  indistinguishable from a panel in front of a hardcoded rule. A typical decision has 53 candidates,
  52 of them refused, each with a score, an edge, a cost total and a reason.
- **Utilisation read back out of refusals the engine actually issued**, not a gauge the UI invented.
  The binding limits live in `crates/risk-engine` and onchain in `RiskGuard`; the panel says so, and
  it refuses to draw a bar it cannot source.
- **The journal's `evidence` array**, which nothing in the v1 UI displayed. It is the per-decision
  half of the chain-of-evidence idea: the exact chain reads a decision rests on.
- **Baseline control rows marked `[baseline]` and excluded from every agent statistic.** Task 1.16's
  DuckDB aggregation found 8 of them contaminating the river benchmark, inflating its margin from
  2.5 points to 11.5. The UI does not repeat that.

## Four defects this phase found in itself

Each was found by a check in this phase, not by review.

1. **The density metric measured nothing.** The first version marked any element with a background
   as occupied, so panel backgrounds covered the viewport and it reported 100% occupied with a
   zero-size largest empty rectangle. It would have passed the gate while proving the opposite.
   Fixed to measure text-run rects.
2. **Panel headers rendered zeros when the source was unreadable.** "0 decisions", "0 refusals",
   "0 of 0". Each was derived from an empty array and each was a false statement about the agent.
   With the source in an error state they now render an em dash.
3. **Impossible values rendered as data.** The red team fed a 20-digit block number and a confidence
   of 999999999 bps, and the UI printed "10000000.0%". Basis points are hundredths of a percent, so
   that is not a percentage. Domain validation now flags the row, prints `invalid` instead of the
   value, and counts out-of-range rows separately from malformed lines.
4. **An invented threshold in the seam test.** It asserted drift <= 20 blocks and the first real
   transaction came in at 29. Loosening the bound after seeing the result would be choosing the
   threshold to fit the answer, so the bound was removed: direction is asserted for all 39
   submissions and the magnitude is reported as the latency measurement it is.

## The two things this phase does NOT claim

**Density does not meet its baseline.** 5.92% against 3.9%. The remaining void is the Learning
panel, which holds one signal statistic because the learning layer has settled exactly 2 forecasts.
It fills as forecasts settle in task 8.5. No decorative panel, sparkline or hero number was added to
win the metric, because "oversized cards with three numbers" and "placeholder charts" are named
failure conditions and passing the number by failing the intent is not a pass.

**Read-to-landing latency is 22 to 30 seconds.** That is not presented as fast. It is the cost of
the signing path ADR-008 records: a `cast` subprocess per transaction, paying a process spawn and a
scrypt keystore decrypt. Task 6.6 weighs alloy's in-process signer against it, and this distribution
is the before-number.

## The step that closed two findings at once

Task 4.5 and 4.1 were both blocked on the same missing build step, not on code: the staged journal
was the 9 Aug file, whose 40 limit refusals carry wei-scaled numbers from before the
`wei_to_micro` conversion. A 40-cycle agent run wrote 43 fresh rows with 39 transactions and 280
real refusals; the pre-fix rows were split to `evidence/journal-legacy-2026-08-09.jsonl` rather than
deleted, with the boundary verified on each half.

With **no CSS and no component change**, ink coverage went 46.63% to 59.83% and the largest empty
rectangle 8.10% to 5.92%. That is the evidence that the layout was sized for content it did not yet
have, and the reason padding it would have been the wrong fix.
