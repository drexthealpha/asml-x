# Task 13.3: the growth loop is legible in under two minutes

Run 2026-08-16. Measured in the Browser pane against the built app.

## PASS condition

A reader reaches the loop from the landing page in under two minutes, timed.

## Measured

```
navigations needed        0        the loop is ON the landing page
time to first live number 0 ms     present in the first paint after metrics load
scroll to reach it        305 px    one scroll, no interaction
stages showing a number   5 of 5
sources named on screen   5
```

**Two minutes was the budget. It took zero navigations and one scroll.**

The shortest path to "reachable in under two minutes" is for the loop to BE on the landing surface,
so reaching it is a scroll rather than a journey. It sits below the explainer, so Connect remains the
primary action and task 9.2's above-the-fold measurement is unaffected.

## The loop, with the numbers it showed

```
1  More callers ask              7        external agents request quotes from the coordination API
2  More actions execute         52        each accepted decision becomes an onchain transaction
3  More fee events fire         11        every execution charges the usage fee, unskippable
4  More decisions are recorded  2,739     each cycle scores a full candidate set, not just the winner
5  More forecasts settle         2        settled outcomes are what the learning layer learns from

   Revenue collected so far      0.088313 tQUOTE
```

Each stage prints its own source underneath it on screen, five of five:

- coordination calls: `evidence/phase6/accepted-quotes.jsonl`, accepted external quotes
- agent actions: `evidence/journal.jsonl`, rows carrying a tx_hash
- fee events: `FeeCollector.chargeCount()`, read from contract state
- candidates: `evidence/journal.jsonl`, summed candidate arrays
- learning: `ui-v2/public/data/learned-state.json`, settled forecasts

## The fake win, refused

Named: "a diagram with no live numbers in it."
Counter: "each stage of the loop must show its current measured value."

The loop is drawn with text and borders, not an image. A diagram asset cannot show a live number, and
one that must be regenerated when a counter moves will eventually stop matching the counter. Every
figure above is read from `metrics.json` at render time.

A stage whose source cannot be read renders the word **unavailable**, never a zero, because "this
happened none times" and "nobody could read it" are different claims. Task 13.1's no-data proof
exercises exactly that path for every counter.

## What is deliberately NOT claimed

These are small numbers and the panel says so on screen: *"This is a small system: the numbers above
are what it has actually done, and no scale is claimed beyond them."*

Two settled forecasts is not a trained model. Seven coordination calls is one external agent. The
loop is real and running; its magnitude is not impressive and pretending otherwise would undo the
point of measuring it.

## A defect this task found

The panel first rendered "absent from the metrics file" for the whole block, and the error was
correct for the wrong reason. `loadMetrics` maps named fields one at a time, which is where
snake_case becomes camelCase and a missing field becomes an explicit null. A new block in
`metrics.json` is therefore invisible to the UI until it is mapped, and `growth` was not.

The panel read it through an `unknown` cast, which is what let the mistake compile. The cast is gone
and `growth` is a typed field like everything else, so the next block that is added to the JSON and
forgotten in the mapper will fail the build rather than render an error at runtime.

## GATE: PASS

Zero navigations, one scroll, five of five stages carrying live measured values with their sources
named on screen.
