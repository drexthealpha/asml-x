# Task 13.1: live growth counters, each with its source

Run 2026-08-16 09:17:54 UTC.

## Every counter, its value and where it came from

```
feesCollectedWei       88312500000000000        <- FeeCollector.totalCollected(token), read from contract state
feeEvents              11                       <- FeeCollector.chargeCount(), read from contract state
agentActions           52                       <- evidence/journal.jsonl, rows carrying a tx_hash
candidatesEvaluated    2739                     <- evidence/journal.jsonl, summed candidate arrays
refusalsTotal          2668                     <- evidence/journal.jsonl, unchosen candidates
refusalsByReason       8 reasons                <- evidence/journal.jsonl, unchosen candidates grouped by rejecti
volumeTouchedMicro     60799990                 <- evidence/journal.jsonl, size x price parsed from the action te
learningUpdates        2                        <- ui-v2/public/data/learned-state.json, settled forecasts
coordinationCalls      7                        <- evidence/phase6/accepted-quotes.jsonl, accepted external quote
```

Three kinds of source, each named as what it is:

| kind | strength |
|---|---|
| **chain** | an eth_call or a decoded log. The strongest: nobody can write to it but the chain. |
| **journal** | the agent's own append-only record. Strong for what the agent did, and it is the agent's account of itself. |
| **file** | a generated artifact, itself produced by one of the above. Weakest, and labelled. |

## The no-data proof

Each source is removed in turn and the counter re-read. A counter must report an ERROR with no
value. A zero would read as "nothing happened", which is a different claim from "nothing could
be read", and conflating them is the failure this gate exists to prevent.

```
journal removed            agentActions: ERROR, no value key  <- correct
journal removed            candidatesEvaluated: ERROR, no value key  <- correct
journal removed            refusalsTotal: ERROR, no value key  <- correct
learned-state removed      learningUpdates: ERROR, no value key  <- correct
accepted-quotes removed    coordinationCalls: ERROR, no value key  <- correct
```

## Why the fee counters cannot tick on a timer

`feesCollectedWei` is `FeeCollector.totalCollected(token)` and `feeEvents` is
`FeeCollector.chargeCount()`, both read from contract state. Re-running this script without new
activity produces identical numbers, because nothing here is derived from elapsed time.

Task 7.4's theorem 5, check_totalCollectedAccumulatesExactly, proves symbolically that the
state total equals the sum of the emitted events, so reading state is not a shortcut around
summing logs: it is provably the same number obtained in two calls instead of hundreds.

## A defect this task found

`volumeTouchedMicro` first reported **0**, because it summed a `notional_micro` field on each
candidate and no such field exists. Candidates carry scoring components
(`expected_edge_micro`, `capital_cost_micro`, `score_micro`) and the size lives in the action
text the runtime wrote. A counter that reads 0 because it is looking at the wrong key is exactly
the failure this gate is written against, and it was caught by the source label not matching
what the data actually contains.

It now parses size and price out of the action text, and REPORTS HOW MANY ROWS IT COULD PARSE,
so a partial parse is visible rather than silently understating volume.

## A second defect, in the fee fetch

The ADR-017 redeploy changed the FeeCollector address, which invalidated the log cache and
forced a cold backfill of several hundred sequential 100-block windows. That ran past the
caller's timeout, the caller deleted the output file, and every fee counter reported an error
even though the totals had already been fetched successfully in two calls.

The log scan now runs under its own wall-clock budget and the totals are emitted regardless. A
partial scan reports `recent_is_complete: false`. This is the third time in this build that a
failure in a decorative part was allowed to destroy an essential one.
