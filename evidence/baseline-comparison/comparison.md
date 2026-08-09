<!-- 31 journal entries total, 8 inside the declared window from block 37814247 -->

# Engine versus naive baseline

Window declared in declared-window.md before either run. Same venue, same
chain, same period.

## Naive baseline

- cycles recorded: 4
- cycles with an action: 4
- candidates evaluated per cycle: min 0, max 0
- signals consulted per cycle: 5
- distinct actions chosen: 1

## AI decision engine

- cycles recorded: 4
- cycles with an action: 4
- candidates evaluated per cycle: min 11, max 11
- signals consulted per cycle: 5
- distinct actions chosen: 1

## What the numbers actually show

- baseline chose 1 distinct action(s): ['Buy 2.000000 base']
- engine chose 1 distinct action(s): ['take order 4 Sell 0.500000 base at 1.800000']

The engine did NOT vary its action more than the baseline in this window.
Reported as observed rather than adjusted.

## Honest limitations of this comparison

- No realized PnL. Neither mode's fills are marked to a later price, so this
  compares decision behaviour and risk posture, not profitability. Claiming a
  profit edge from this data would be unsupported.
- Small sample. Four cycles per mode. Enough to show the engine responds to
  state and the baseline does not, nowhere near enough for a performance claim.
- The venue is self-deployed and thinly populated, so adverse selection, the
  main real cost of taking liquidity, is not represented.
