# Task 14.4: realized PnL, closing the learning loop

Run 2026-08-16 16:27:46 UTC. Verdict: **PASS**

## What was missing

The loop already measured a hit rate and an edge error in basis points. **That grades
forecasts, not trading.** A signal can be right most of the time and still lose money, by being
right on small positions and wrong on large ones, and nothing in the system could tell those
two apart because no size was ever multiplied into a move. `Pending` now carries
`size_micro` and `Outcome` carries `realized_pnl_micro`.

## The arithmetic, and where the sign lives

```rust
let price_delta = current_mid - p.mid_at_decision;
let directional = match p.predicted {
    Predicted::Up   =>  price_delta,
    Predicted::Down => -price_delta,   // a short gains when the price falls
    Predicted::NoView => 0,
};
let realized_pnl_micro = (p.size_micro * directional) / MICRO;
```

Integer arithmetic throughout, because the workspace lint denies floats in this crate. The
division by `MICRO` happens ONCE: size and the price delta are each micro-scaled, so their
product is micro-squared. Truncation is toward zero and that is deliberate, since the rounding
that would flatter the result is the one that rounds a loss up to zero.

## The sign mutation

`directional` was negated, inverting every PnL:

```rust
- let realized_pnl_micro = (p.size_micro * directional) / MICRO;
+ let realized_pnl_micro = (p.size_micro * -directional) / MICRO;
```

**3 tests went red:** `a_wrong_call_produces_a_negative_pnl long_that_rises_makes_money_proportional_to_size short_that_falls_makes_money_and_the_sign_is_not_inverted `

That is the failure worth guarding: an inverted sign makes a losing system report profits, and
it passes every direction-based test in the crate, because direction is scored separately from
PnL. Restored: `test result: ok. 23 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s`

## Where the outcome is recorded, and why not in `journal.jsonl`

Settlements are appended to `evidence/settlements.jsonl`, keyed by `decision_id`. Three
options existed and ADR-020 records the reasoning:

1. **Rewrite the original journal row.** Rejected outright. Append-only is the property the
   whole evidence chain rests on. A journal that can be edited after the fact cannot be cited
   as a record of what was decided at the time.
2. **Append settlement rows into `journal.jsonl`.** Rejected on a MEASURED cost: twenty-odd
   consumers read that file line by line and index `r["candidates"]` and `r["tx_hash"]`
   directly, so a differently-shaped row breaks the growth counters, the UI data build and the
   scale audit at once.
3. **An append-only sidecar keyed by `decision_id`.** Chosen.

**This also fixes a real defect.** The `outcome` field on a journal row was filled with
whatever settled during THAT cycle, which is a different decision made a minute earlier. A row
for decision 163 carried decision 87's result. A settlement now names the decision that made
the prediction.

## Settlements produced by this run

0 new settlement row(s); 3 total.

```
{
    "basis": "mark to market: size * (mid_at_settle - mid_at_decision), signed by direction",
    "decision_id": 87,
    "direction_correct": true,
    "edge_error_micro": "-272920",
    "expected_edge_micro": "274920",
    "mid_at_decision": "2250000",
    "mid_at_settle": "1800000",
    "predicted": "down",
    "realized_move_bps": "-2000",
    "realized_pnl_micro": "0",
    "record": "settlement",
    "settled_at_ms": 1786895063000,
    "signal_name": "imbalance_bps",
    "size_micro": "0"
}
{
    "basis": "mark to market: size * (mid_at_settle - mid_at_decision), signed by direction",
    "decision_id": 175,
    "direction_correct": false,
    "edge_error_micro": "-60319",
    "expected_edge_micro": "59208",
    "mid_at_decision": "1800000",
    "mid_at_settle": "2000000",
    "predicted": "down",
    "realized_move_bps": "1111",
    "realized_pnl_micro": "-37500",
    "record": "settlement",
    "settled_at_ms": 1786895794000,
    "signal_name": "imbalance_bps",
    "size_micro": "187500"
}
{
    "basis": "mark to market: size * (mid_at_settle - mid_at_decision), signed by direction",
    "decision_id": 176,
    "direction_correct": false,
    "edge_error_micro": "-60319",
    "expected_edge_micro": "59208",
    "mid_at_decision": "1800000",
    "mid_at_settle": "2000000",
    "predicted": "down",
    "realized_move_bps": "1111",
    "realized_pnl_micro": "-37500",
    "record": "settlement",
    "settled_at_ms": 1786895794000,
    "signal_name": "imbalance_bps",
    "size_micro": "187500"
}
```

### Joined to the decision that made the prediction

```
decision 87
  NO MATCHING JOURNAL ROW. The join failed and that is a defect, not a formatting gap.
decision 175
  decided at block 38436806, action take order 5 Sell 0.187500 base at 1.900000
  thesis            BOOK IS CROSSED: best bid 1.900000 is at or above best ask 1.700000, so spread-based inf
  predicted         down on imbalance_bps
  size              187500 micro base
  mid at decision   1800000
  mid at settle     2000000
  realized move     1111 bps, direction correct False
  expected edge     59208 micro
  edge error        -60319 micro
  REALIZED PNL      -37500 micro quote

decision 176
  decided at block 38436845, action take order 5 Sell 0.187500 base at 1.900000
  thesis            BOOK IS CROSSED: best bid 1.900000 is at or above best ask 1.700000, so spread-based inf
  predicted         down on imbalance_bps
  size              187500 micro base
  mid at decision   1800000
  mid at settle     2000000
  realized move     1111 bps, direction correct False
  expected edge     59208 micro
  edge error        -60319 micro
  REALIZED PNL      -37500 micro quote

```

The join is on `decision_id`, so the outcome is attached to the reasoning that produced it:
the thesis, the candidates considered and the size taken are all one lookup away from the
money the decision made or lost. That is what closing the loop means here.

**A forecast driven all the way to a NON-ZERO PnL is in**
`evidence/phase14/pnl-settlement.md`. It needed its own step: this venue's book is static, so
the mid never moves and the 5 bps dead band correctly drops every forecast as unscoreable.
`scripts/169-settle-with-real-move.sh` posts a real order that moves it.

## What is claimed, and what is not

**Claimed:** a signed realized PnL in micro quote units, recorded against the decision that
made the prediction, carrying every input it was computed from so a reader can recompute it.

**NOT claimed:** cash proceeds. This is MARK TO MARKET against a later observed mid, not the
result of a closing trade, and the `basis` field on every settlement row says so in those
words. Calling it realized cash would be claiming a round trip that did not happen.

## Reproduce

```
bash scripts/168-realized-pnl.sh
```
