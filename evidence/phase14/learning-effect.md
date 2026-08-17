# Task 14.6: the learning effect, with its sample size

Run 2026-08-16 19:13:57 UTC. Verdict: **PASS**

## The named fake win, and the structural counter

The fake win is **a chart trending up**. A rising line on ten points is a picture of noise, and
it is the single most persuasive thing this panel could have shown while proving the least.

The counter is structural rather than editorial. The sample count is stored INSIDE the same
object as the figure it governs, so a component cannot render the number without having been
handed the sample as well. Making the honest framing the path of least resistance beats relying
on whoever writes the next component to remember.

Check: PAIRED

## What is actually on screen

```
settled outcomes   10
dropped as flat    36   (market did not move; unscoreable, not wrong)
signal hit rate    40.0%  (n = 10)

net move, from the defaults it started at:
  momentum_weight_bps      2000 -> 391
  variance_weight_bps      8000 -> 8000   (unchanged)
  thin_book_penalty_bps    150 -> 1225

realized PnL       337500 micro quote over 8 settlements
                   3 up, 4 down, 1 flat
                   mark to market against a later observed mid, not cash proceeds
```

## Why the NET move is shown above the per-change list

The learner clamps every step, so the individual moves are small: the change list reads
`411 -> 401` and a reader concludes nothing happened. The net move says momentum weight has
fallen from its default of 2000 to 391. Same run, two descriptions, and only the second answers
"has this learned anything".

**A defect was found doing this.** The learner wrote its parameter history on save and silently
dropped it on load, so the recorded history was only ever the current process's changes. That is
the same shape as the pending-queue bug fixed earlier, where short runs learned nothing while
reporting `settled 0`. Fixed, with `parameter_history_survives_a_reload` pinning it: disabling
the restore turns that test red and nothing else.

## The direction of the effect is not softened

The hit rate is **below a coin flip** and the learner responded by cutting the momentum weight
toward its floor and raising the thin-book penalty eightfold. That is the system working: it
noticed the signal was not paying and stopped leaning on it. During the sample run the agent
went on to choose `hold` outright. Presenting that as a setback would present a working
feedback loop as a defect; presenting it as a profit would be a lie.

## The no-data test

`learned-state.json` was removed and the metrics rebuilt:

| state | figures reporting ERROR |
|---|---|
| source removed | 4 |
| source restored | 0 |

A failed read yields an `error` key and **no `value` key at all**, so a consumer cannot
render a number it was never given. Zero and unreadable look identical on screen and mean
opposite things, which is why the shape enforces it rather than a convention.

## Patterns applied

`ui-v2/src/components/learning-effect-panel.tsx` cites `orderbook-row.tsx:34`,
`orderbook-panel.tsx:151-153` and `orderbook-panel.tsx:121-137` from evidence/ui-study.md.

## Reproduce

```
bash scripts/174-learning-effect.sh
```
