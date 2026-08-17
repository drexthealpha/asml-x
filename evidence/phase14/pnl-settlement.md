# Task 14.4, part two: a forecast settled to a non-zero realized PnL

Run 2026-08-16 15:57:28 UTC. Verdict: **PASS**

3 settlement(s) recorded, 2 with a non-zero PnL, 2 new in this run.

## Why this needed its own step

`scripts/168-realized-pnl.sh` proved the arithmetic by inverting the sign and watching three
tests go red. What it could not do was run the path end to end on a real position, for two
reasons that are both the system working correctly:

1. Forecasts recorded before 14.4 carry no size, so their PnL is correctly zero.
2. The seeded book is **static**. The mid never moved, so every new forecast was dropped by the
   5 bps dead band as unscoreable rather than settled. A market that did not move cannot judge a
   directional call, and scoring it would manufacture a hit rate out of noise.

So the settlement path was tested and had never once executed on a real position. Recording
14.4 as done on that basis would have been a green nobody had tried to break.

## What was done, stated plainly

The venue is a **self-deployed stand-in**, as labelled throughout this repo. A real order was
posted to it that moves the mid past the dead band. That is a genuine onchain price move in a
real transaction, and the PnL below is real arithmetic over it.

**This is NOT a claim that the agent predicted an exogenous market.** The move was caused
deliberately, to exercise a code path that this venue would otherwise never reach. What is
demonstrated is that a decision's outcome flows back to the decision that made it, carrying a
signed figure in money rather than only a direction.

## The settled decision

```
decision 176
  decided at block   38436845
  action             take order 5 Sell 0.187500 base at 1.900000
  thesis             BOOK IS CROSSED: best bid 1.900000 is at or above best ask 1.700000, so spread-based i
  predicted          down on imbalance_bps
  size               187500 micro base
  mid at decision    1800000
  mid at settle      2000000
  realized move      1111 bps
  direction correct  False
  expected edge      59208 micro
  edge error         -60319 micro
  REALIZED PNL       -37500 micro quote
```

Recomputed from the row's own fields:

```
  price delta      2000000 - 1800000 = 200000
  direction        predicted down, so signed delta = -200000
  pnl              187500 * -200000 / 1000000 = -37500
  recorded         -37500
  agree            True
```

**The PnL is negative, and that is left exactly as it came out.** The agent was short and
the mid was pushed up, so the position lost. A gate that only ever demonstrated a profit
would be selecting its evidence; the loop is closed whichever way the number falls, and a
system that can only record its wins is not measuring anything.

## Reproduce

```
bash scripts/169-settle-with-real-move.sh
```
