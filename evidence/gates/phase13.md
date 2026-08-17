# Phase 13 gate: the growth surface

Closed 2026-08-16.

**CLOCK STOPS HERE (TASKS.md):** the growth mechanism is running and visible, without claiming scale
we do not have.

## Subtasks

| # | task | gate | verdict |
|---|---|---|---|
| 13.1 | live counters, read from chain | `bash scripts/161-growth-counters.sh` | PASS, 9 counters, no-data proof on each |
| 13.2 | coordination metering | `bash scripts/160-coordination-metering.sh` | PASS, per-caller usage and a quoted fee |
| 13.3 | the loop legible in under 2 minutes | `bash scripts/161-growth-counters.sh` + browser | PASS, 0 navigations, 0 ms |

Claims C-1300, C-1301, C-1302.

## The counters, each with its source

```
feesCollectedWei     88313000000000000   FeeCollector.totalCollected(token), contract state
feeEvents            11                  FeeCollector.chargeCount(), contract state
agentActions         52                  evidence/journal.jsonl, rows carrying a tx_hash
candidatesEvaluated  2,739               evidence/journal.jsonl, summed candidate arrays
refusalsTotal        2,668               evidence/journal.jsonl, unchosen candidates
refusalsByReason     8 reasons           grouped by rejection_reason
volumeTouchedMicro   60,799,990          size x price parsed from the action text
learningUpdates      2                   learned-state.json, settled forecasts
coordinationCalls    7                   accepted-quotes.jsonl, accepted external quotes
```

Three kinds of source, each labelled as what it is: **chain** (an eth_call or decoded log),
**journal** (the agent's own record), **file** (a generated artifact).

## The no-data proof

Each source removed in turn, then the counter re-read:

```
journal removed          agentActions:        ERROR, no value key   <- correct
journal removed          candidatesEvaluated: ERROR, no value key   <- correct
journal removed          refusalsTotal:       ERROR, no value key   <- correct
learned-state removed    learningUpdates:     ERROR, no value key   <- correct
```

The shape enforces it: a failed counter carries no `value` key at all, so a consumer cannot render a
number it was never given. `undefined` is not `0`.

## FAKE WIN REGISTER

| named fake win | fired? |
|---|---|
| 13.1 a counter that ticks on a timer | No. Nothing is time-derived; re-running without new activity gives identical numbers. |
| 13.3 a diagram with no live numbers in it | No. The loop is text and borders, and all 5 stages read from metrics.json at render time. |

## Defects this phase found

**1. `volumeTouchedMicro` reported 0** because it summed a `notional_micro` field that does not exist
on a candidate. Candidates carry scoring components (`expected_edge_micro`, `capital_cost_micro`,
`score_micro`) and the size lives in the action text. A counter reading 0 because it looks at the
wrong key is exactly what this gate is written against. It now parses size and price out of the
action text AND reports how many rows it could parse, so a partial parse is visible.

**2. The fee fetch was killed by its own decoration.** The ADR-017 redeploy changed the FeeCollector
address, invalidating the log cache and forcing a cold backfill of several hundred sequential
100-block windows. That ran past the caller's timeout, the caller deleted the output file, and every
fee counter reported an error even though the totals had already been fetched successfully in two
calls. The log scan now has its own wall-clock budget and the totals are emitted regardless.

**This is the third time in this build that a failure in a decorative part destroyed an essential
one**, after `|| echo '[]'` manufacturing a zero fee total in Phase 7 and `|| echo n/a` hiding a
wrong `cast estimate` invocation in Phase 11.

**3. A new metrics block was invisible to the UI.** `loadMetrics` maps fields one at a time, so
`growth` did not reach the component and the panel rendered "absent from the metrics file", which was
correct for the wrong reason. The panel had read it through an `unknown` cast, which is what let it
compile. The cast is removed and `growth` is typed, so the next forgotten mapping fails the build.

## What is deliberately NOT claimed

Two settled forecasts is not a trained model. Seven coordination calls is one external agent. The
panel states this on screen rather than in a footnote: *"This is a small system: the numbers above
are what it has actually done, and no scale is claimed beyond them."*

Coordination usage is **priced, not billed**. The API is unauthenticated by design with no privileged
path, and charging would need an identity system this project did not build. The evidence says
"usage is measured and priceable at a rate that already exists onchain", not "usage is monetised".
