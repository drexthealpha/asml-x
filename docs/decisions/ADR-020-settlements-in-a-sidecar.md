# ADR-020: settlements go in an append-only sidecar, not in the journal row

Status: ACCEPTED, 2026-08-16. Task 14.4.

## The problem

A decision's outcome is not known when its journal row is written. The row is appended at decision
time; the realized PnL exists a minute later, after the settlement lag has elapsed and the mid has
moved. Something has to connect them.

There was also a live defect. `Entry.outcome` was being filled with whatever settled during **that
cycle**, which is a different decision made a minute earlier. Decision 163's row carried decision
87's result. Anyone reading a journal row and taking `outcome` as that row's outcome was reading
another decision's number.

## What was considered

**1. Rewrite the original row in place when it settles.** Rejected outright, and not on effort. The
journal is append-only, and that property is what the entire evidence chain rests on: a record that
can be edited after the fact cannot be cited as evidence of what was decided at the time. Buying a
tidy `outcome` field at the cost of the journal's integrity is the worst trade available here.

**2. Append settlement rows into `journal.jsonl` with a `record` discriminator.** Rejected on a
**measured** cost, not a guess. Twenty-odd consumers read that file line by line and index
`r["candidates"]` and `r["tx_hash"]` directly. A differently-shaped row breaks the growth counters
(`patch_growth_counters.py`, `recompute_metrics.py`), the UI data build (`78-ui-data.sh`) and the
scale audit (`journal_scale_audit.py`) at once. Every one of those would have to learn to filter, and
each is a place a future reader forgets to.

**3. An append-only sidecar, `evidence/settlements.jsonl`, keyed by `decision_id`.** Chosen.

## Decision

Settlements are appended to `evidence/settlements.jsonl`. Each row carries `decision_id`, joining to
`journal.jsonl`, plus **every input the PnL was computed from**: `mid_at_decision`, `mid_at_settle`,
`size_micro`, `predicted`, `realized_move_bps`, `expected_edge_micro`, `edge_error_micro` and a
`basis` string.

Carrying the inputs and not just the result is the point. A settlement reporting only a number would
be unauditable: nobody could tell a real move from an arithmetic slip. Because the inputs are there,
`169-settle-with-real-move.sh` recomputes the PnL in Python from the row's own fields and compares it
to what the Rust engine wrote, which is the same differential idea as ADR/claim C-1400.

## Consequences

- The join is one lookup: a decision's thesis, candidates and chosen size sit beside the money it
  made or lost.
- The outcome is attached to the decision that **made the prediction**, fixing the mismatch above.
- Every existing journal consumer keeps working unchanged.
- A reader must open two files to see a decision and its outcome. That is the cost, and it is the
  right one to pay for an append-only journal.

## What is NOT claimed

`realized_pnl_micro` is **mark to market** against a later observed mid, not cash proceeds from a
closing trade. Every row says so in its `basis` field, and the evidence files say so in words.
Calling it realized cash would claim a round trip that did not happen.

## Revisit condition

If a closing trade is ever executed against a position, a `realized_cash_micro` field is added
alongside rather than replacing this one, so the mark-to-market figure and the settled figure can be
compared instead of one silently becoming the other.
