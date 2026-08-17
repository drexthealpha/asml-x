# The burst stall: diagnosed properly, then fixed

Tasks 6.1, 6.2, 6.3. v1 left this open with the honest note "the diagnosis was wrong and the cause is
still open", and marked the rate limiter's 429 path INFERRED because it had never been seen to fire.

## What v1 got wrong

v1 observed the server stop responding during a 40-request burst, concluded a slow or half-open client
was parked in `read_line`, and added 3-second per-socket read and write timeouts. That did not work,
and the gate report said so rather than pretending otherwise.

The timeouts could not have worked. A deadline on each socket does not shorten a queue, and the queue
was the problem.

## What was actually wrong: three separate defects

**1. Every request walked the order book.** A cold `read_snapshot` issues `orderCount()` and then one
`orders(i)` call per order: about 35 sequential RPC round trips, measured at **34,311 ms** for 35 live
orders. The first request paid that, and every other request queued behind it. This is also an
amplification vector: one unauthenticated HTTP request became 35 round trips against a public RPC.

**2. The server read a request body on GETs.** `request.as_reader().read_to_string(...)` asks the
transport for bytes the client never promised. curl closes its side promptly so the read hits EOF;
Python's urllib holds the connection, so the read blocked until the client's own 30-second timeout.
That is why curl measured `/thesis` at 0.57 ms while the Python agent timed out against the same
server, and why `/health` kept answering throughout: it returns before that read.

**3. The socket was bound before the cache was primed.** `Server::http` binds immediately, so
connections sat in the kernel backlog during the 35-second book read. Measured: `/health` took
**23.1 s** on a server that answers it in under a millisecond once running.

## The fix

- **tiny_http 0.12** owns HTTP parsing, which deletes the hand-written request-line, header and
  content-length handling. Chosen per R-SEARCH-3: the hand-rolled parser had already cost more than
  one debugging attempt.
- **8 worker threads** over `Arc<Server>`, the pattern from tiny_http's own documentation, with shared
  state behind one `Mutex` that is never held across a chain read.
- **One refresher thread owns every chain read.** The request path touches the chain zero times. The
  cache is primed BEFORE the socket binds, and a view older than `MAX_SERVE_AGE_MS` is refused with
  its age rather than served silently.
- **Body reads are gated** on method and a declared content-length.

`MAX_SERVE_AGE_MS` is 120,000, set from the measured 34,311 ms refresh rather than a number that
sounded right. The first draft used 10,000, which is shorter than one refresh cycle: the endpoint
would have spent most of its life returning 503 while working perfectly.

## Measured, before and after

| | before | after |
|---|---|---|
| 40-request burst | **802 s, 40 timeouts** | **0.28 s** |
| burst result codes | 40 x client timeout | **18 x 200, 22 x 429** |
| `/thesis` | never answered | **0.00057 s** |
| `/capacity` | never answered | **0.00052 s** |
| `/health` during startup | 23.1 s | **0.0016 s** |
| chain reads per request | up to 35 | **0** |
| server alive after burst | not reached | yes, `/health` in 0.0005 s |

## 6.3: the rate limiter, observed

From `evidence/phase6/rate-limit-429.txt`, the agent's own words:

```
9. adversarial: burst until the rate limit trips
  rate limit tripped on request 20
        -> OK: rate limit enforced
```

`ASML_RATE_LIMIT=20`, and it tripped on request 20. This moves the 429 path from INFERRED to
DEMONSTRATED. It was never observable before because the burst could not complete.

## 6.1: the full suite

`bash scripts/26-coordination-live.sh` with `ASML_RATE_LIMIT=20`:
**14 checks passed, 0 failed**, exit 0. Covering the happy path, quote and accept, wrong caller (403),
missing and unknown key (401), malformed body (400), risk refusal (409), expired quote (410), the
rate limit (429), and an unknown endpoint (404). Full log:
`evidence/phase6/external-agent-full.log`.

## A fourth defect, in the tooling rather than the product

Three suite runs produced no output and left the logs untouched, which looked exactly like the stall
returning. The cause was `pkill -f asml-coord` inside `wsl -- bash -c '...'`: the invoking shell's own
argv contains that string, so `pkill -f` killed the shell that ran it. Nothing after it executed.

The same bug in its `pgrep -f` form is why a dead `cargo mutants` run reported "still running" for an
hour earlier in this build. Both are now `-x`, which matches the process name only, and it is recorded
as E13 in CLAUDE.md.

Worth stating because it nearly produced a wrong conclusion twice: a measurement harness that lies
about whether something ran is more dangerous than the bug it was pointed at.
