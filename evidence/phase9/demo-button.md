# Task 9.6: one-click Run Full Demo

Run 2026-08-16 04:09:56 UTC. Endpoint: POST /demo on the coordination API.

The button spawns the runtime's own `asml run 1`, which is exactly what
scripts/18-agent-driven-run.sh invokes. Nothing is simulated and nothing is replayed.

## Ten consecutive runs

```
run  http     journal      block      verdict                                    seconds
1    ok       60->61       38394562   approved,_0_candidate(s)_refused_by_risk   16.9
2    ok       61->62       38394578   approved,_0_candidate(s)_refused_by_risk   14.0
3    ok       62->63       38394593   approved,_0_candidate(s)_refused_by_risk   16.8
4    ok       63->64       38394608   approved,_0_candidate(s)_refused_by_risk   13.9
5    ok       64->65       38394623   approved,_0_candidate(s)_refused_by_risk   12.0
6    ok       65->66       38394636   approved,_0_candidate(s)_refused_by_risk   14.5
7    ok       66->67       38394650   approved,_0_candidate(s)_refused_by_risk   13.3
8    ok       67->68       38394665   approved,_0_candidate(s)_refused_by_risk   17.6
9    ok       68->69       38394680   approved,_0_candidate(s)_refused_by_risk   13.8
10   ok       69->70       38394696   approved,_0_candidate(s)_refused_by_risk   15.6
```

## Gate

- runs:                 10
- failures:             0  (a single failure fails this task)
- runs with no new row: 0  (the replay check)
- repeated blocks:      0  (the replay check)
- slowest run:          17.6s (run 8)

GATE: PASS  10 consecutive runs, 10 successes, each writing a new journal row.

## What the ten runs showed

All five things the task asks for, on every run:

| element | shown |
|---|---|
| thesis | "BOOK IS CROSSED: best bid 1.900000 is at or above best ask 1.700000, so spread-based inference is unreliable; depth is ask-heavy by 2666 bps" |
| risk decision | approved, 0 candidates refused by risk, 25 candidates scored |
| execution | a real transaction per run, new block each time |
| journal entry | rows 60 through 70, one per run |
| fee event | `FeeCharged` decoded from the receipt |

Fee decoded from `0x6e6d290cc9dafe3a74e78bb60ddc9faf42cd912fd47eb7ba2f1cf3935266c500`, from the
receipt and not from local state:

```
payer     0x954a0b68b81dd4028631a7d1b98d80bf2a563142   (the BatchExecutor)
notional  2850000000000000000
feeAmount   14250000000000000
feeBps                     50
check     2850000000000000000 * 50 / 10000 == 14250000000000000  ->  True
```

The agent is honest about its own uncertainty while acting: it took the trade AND flagged that a
crossed book makes its usual spread-based inference unreliable.

## Two defects this task exposed, both fixed

**1. The seeded book had nothing worth trading.** `scripts/17-seed-book-and-observe.sh` posts asks at
2.10 and 2.20 against bids at 1.90 and 1.80: mid 2.00, spread 1000 bps. Crossing that costs more than
the available edge, so the agent scored hold above every take, ten runs out of ten. That is the risk
engine working correctly, and the first version of this evidence file recorded it as an honest
limitation of the demo.

That was the wrong call. The task asks the button to show an execution and a fee event, and writing
down why it does not is documenting a defect rather than fixing one.

The fix is NOT to make the agent less cautious. `scripts/136-seed-executable-book.sh` posts an ask at
1.70 while a bid of 1.90 is resting: a crossed book, where base is for sale for less than someone is
already paying. An agent that declined that would be broken. The agent's judgement is untouched; the
market it judges now contains a trade worth taking. Candidates went from 9 to 25 and the verdict from
`hold` to `approved`.

**2. A regression introduced in task 7.6.** `scripts/submit-take.sh` used to carry TWO `approve` legs
per batch, with a comment stating exactly why: "A take against a resting bid makes us the seller,
which moves base out of the executor, while a take against a resting ask moves quote out. The runtime
does not tell this script which side it chose, so both allowances are set."

Task 7.6 removed those legs to save roughly 24k gas per execution and moved the grant to a one-time
`approveToken` at deploy time, but granted only tQUOTE. The code that made the comment true was
deleted and the comment was left behind.

It stayed hidden because every execution between Phase 7 and here was a BUY, which spends quote. The
first SELL reverted with `LegFailed(1, venue, ...)` on `take(uint256,uint256)`: the venue could not
pull tBASE from the executor.

Both tokens are now granted at deploy, and the executable-book seeder re-asserts them. The gas
optimisation was correct in arithmetic and wrong in spirit: the per-batch legs were idempotent and
self-healing, while a one-time grant is setup that can be incomplete, and was.

## Three smaller things

- **The port and the key were assumed rather than read.** The first version of the gate and the UI
  pointed at `:8080` with no auth header. The API binds `:8737` and requires `x-api-key`, and it
  PRINTS both in its startup banner. The gate spent 90 seconds polling a port nothing was bound to.
- **The health check raced the server's startup.** The API primes its cache before binding, roughly
  35 sequential RPC round trips, which is deliberate: a socket that accepts before it can answer is
  worse than one that is not there yet. The gate polls for readiness now.
- **The runtime refuses to journal a single-candidate cycle**, reporting `DEFECT, exactly one
  candidate evaluated, this is not a search`. That self-check is doing its job: it will not dress a
  forced choice up as a search.

## Concurrency

`POST /demo` is guarded by an atomic and returns 429 with a named reason if a cycle is already
running. Two overlapping `asml run` processes would submit from the same key, collide on the nonce,
and the second failure would look like a broken agent rather than a double-click. A judge will
double-click.

## GATE: PASS

Ten consecutive runs, ten successes, each writing a new journal row in a new block. Slowest 17.6s.
