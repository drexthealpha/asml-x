# Phase 10 gate: the cold-user claim, measured

Closed 2026-08-16. Chain 1952.

**CLOCK STOPS HERE (TASKS.md):** the flow claim is measured rather than asserted.

## Subtasks

| # | task | gate | verdict |
|---|---|---|---|
| 10.1 | instrument the flow | `bash scripts/143-flow-timing.sh` | PASS, 5 marks per run, in a file |
| 10.2 | time cold users | `bash scripts/142-cold-user-runs.sh` | PASS, median 8.6 s, 3 runs |
| 10.3 | publish the number | `bash scripts/144-claim-consistency.sh` | PASS, no document disagrees |

Claims C-1000, C-1001, C-1002.

## The number

**8.6 seconds median, first paint to activated, across three cold runs.** Min 8.5 s, max 9.2 s.

```
first paint to connected       about 2.0 s   provider handshake and the first chain reads
connected to defaults seen     about 0.3 s   limits.json is cached at module level
defaults to deposit submitted  about 1.4 s   permit signature plus calldata
submitted to activated         about 4.8 s   waiting for the chain
```

More than half is the chain confirming a block, which the product does not control. The part the
product controls is about 3.8 s.

## THE LABEL THAT MATTERS

**All three runs are SCRIPTED, not human, and every document that carries the number says so.**

The task allows a scripted run where a human tester is unavailable and requires the label, "because a
script does not hesitate and a person does". The named fake win is "timing a run by someone who
already knows where every button is", and a script is the limiting case: it knows exactly where every
button is and takes zero time to decide.

So 8.6 s is **the system's floor**, a lower bound on a human time, useful mainly for catching
regressions because it repeats to the millisecond. No human run has been performed. The README row
and the landing-page line both state "SCRIPTED, not human: a lower bound" rather than implying a
person did it in 8.6 seconds.

## Cold means cold, asserted rather than assumed

`scripts/make-cold.sh` zeroes the allowance and withdraws the balance before every run, and the
values are read back from chain before the browser is touched. This is a direct consequence of task
9.4, where "one click" was measured twice on warm accounts: both readings were true numbers and both
claims would have been false.

## Two defects this phase found

**1. The marks were silently not persisting, and curl said everything was fine.** The endpoint
returned `{"ok":true}` from the shell while `flow-marks.jsonl` stayed empty after a browser run. Two
CORS causes, both invisible to a curl-only test because **curl does not preflight**:

- the API checked `x-api-key` before routing, so the preflight `OPTIONS`, which never carries
  credentials by design, got 401 and the browser blocked the real POST
- `Access-Control-Allow-Headers` listed only `content-type`, so the browser refused to send the key
  even after preflight was answered

Preflight is now answered before auth, and the header list includes `x-api-key`. The lesson is that a
shell test and a browser test disagreed and the shell test looked authoritative.

**2. The first timing run measured the tester, not the product.** The flow was driven from a console
command issued about 15 seconds after page load, and those 15 seconds landed inside
`first_paint to connected`. The cold-run driver now starts from the first rendered frame, gated on a
sessionStorage flag so an ordinary visitor never triggers it.

## Instrument design notes

- `performance.now`, not `Date.now`, for deltas. Wall clock can step backwards when the system clock
  syncs mid-run, producing a negative duration that would be quietly averaged into a headline number.
- Marks are idempotent per run. They fire from React effects, which run twice in StrictMode and again
  on remount; without idempotence "connected" would be re-stamped on every tab change and the elapsed
  time would collapse toward zero, which is the direction that flatters the number.
- Only a connection ON THE EXPECTED CHAIN counts as `connected`. A wallet on the wrong network cannot
  do anything here, and stamping it would credit the flow with a step the user has not completed.
- A failed POST never blocks the flow. Instrumentation that can break what it measures would leave
  the measurement describing a product nobody ships.

## Outstanding

`docs/JUDGE-GUIDE.md` does not exist yet; it is created in Phase 17. The consistency gate reports it
as a missing target rather than a pass, and must be re-run there. A file that does not exist cannot
carry a wrong number, but it cannot carry a right one either.
