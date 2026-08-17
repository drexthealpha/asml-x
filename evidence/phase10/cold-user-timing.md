# Task 10.2: cold-user timing

Run 2026-08-16. Chain 1952. Marks persisted to `evidence/phase10/flow-marks.jsonl`.

## WHAT KIND OF RUN THIS IS

**All three runs below are SCRIPTED, not human.**

The task allows this explicitly where a human tester is unavailable, and requires the label, "because
a script does not hesitate and a person does". The named fake win for this task is "timing a run by
someone who already knows where every button is", and a script is the extreme case of that: it knows
where every button is and takes zero time to decide.

So these numbers measure **the system's floor**: how long the software takes when the decision cost
is zero. That is a genuine lower bound on a human time and it is NOT the headline number for a human
claim. What it is good for is regression detection, because it repeats to the millisecond.

**No human run has been performed.** Any README or JUDGE-GUIDE claim about how long a person takes
must either be measured with a person or must state that the figure is a scripted lower bound.

## Cold state, asserted on chain before every run

`scripts/make-cold.sh` zeroes the allowance and withdraws the vault balance, and the values are read
back from chain before the browser is touched:

```
allowance(user, vault): 0
vault.balanceOf(user):  0
```

This matters because task 9.4 measured "one click" twice on warm accounts, both times a true number
and a false claim. Warmth is easy to acquire by accident, so it is asserted rather than assumed.

## Results

Milliseconds since first paint. Five marks per run, all three runs complete.

```
run                    first_paint  connected  defaults_seen  deposit_submitted  activated
run-msvd715k-1moprr          0        2722         3066            3851             9205
run-msvd9lx5-94h4vu          0        1940         2260            3622             8530
run-msvdbx3p-jqp3oj          0        2149         2494            3817             8620
```

```
runs:    3
median:  8620 ms   (8.6 s)
min:     8530 ms   (8.5 s)
max:     9205 ms   (9.2 s)
```

**Median first paint to activated: 8.6 seconds.** Under the 60 second threshold, so the README says
the measured figure rather than a number over 60.

Transactions from the runs, all confirmed on chain:
`0x05ef26cf...826c52`, `0x35d61682...22f832`, and the run-A transaction recorded in the marks file.

## Where the time actually goes

```
first paint to connected      about 2.0 s   provider handshake and the first chain reads
connected to defaults seen    about 0.3 s   limits.json is cached at module level
defaults to deposit submitted about 1.4 s   permit signature plus calldata
submitted to activated        about 4.8 s   waiting for the chain to confirm
```

More than half the total is the chain confirming a block, which the product does not control. The
part the product does control is roughly 3.8 seconds.

## A defect this task found

The marks were POSTing successfully from `curl` and silently failing from the browser, leaving the
file empty while the endpoint returned `{"ok":true}` on the command line.

Two causes, both CORS, and both invisible to a curl-only test because **curl does not preflight**:

1. The API checked `x-api-key` before routing, so the preflight `OPTIONS` request, which never
   carries credentials by design, got 401 and the browser blocked the real POST.
2. `Access-Control-Allow-Headers` listed only `content-type`, so even after the preflight was
   answered the browser refused to send `x-api-key`.

Preflight is now answered before auth, and the allowed-headers list includes `x-api-key`. Worth
recording because a shell test and a browser test disagreed, the shell test was the one that looked
authoritative, and it was wrong.

## GATE: PASS

Three cold runs, five timestamps each, median 8.6 s recorded. Every run labelled SCRIPTED.
