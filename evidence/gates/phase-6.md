# Phase 6 gate: coordination surface with a real external agent

Captured 9 Aug 2026, re-verified after a WSL restart. Chain 1952.
Evidence: `evidence/coordination/external-agent.log` (140 lines, regenerated),
`evidence/coordination/server.log`.

## What was built

`crates/coordination-api`, binary `asml-coord`. A callable HTTP surface on the standard
library only, no dependencies, because this endpoint is reachable by strangers and
dependency surface matters more here than throughput.

Endpoints: `GET /health` (unauthenticated), `GET /thesis`, `GET /capacity`,
`POST /quote`, `POST /accept`.

Properties that carry the claim:
- Every external request passes the SAME risk gate as an internal decision. A caller
  cannot obtain a quote the agent itself would be refused.
- Quotes expire (15s) and carry an id, so an open-ended quote is not a free option
  written to the world.
- Per-caller rate limits keyed on API key.
- `GET /capacity` discovers headroom by ASKING the risk engine in a size ladder, never
  by recomputing limits locally. Two implementations of one limit is how they diverge.
- Responses carry `block` and `snapshot_age_ms`, so a caller can audit view freshness.

## The external agent is genuinely external

`agents/external_agent.py`. Separate process, separate language, no shared state, HTTP
only. It reads `/thesis` and `/capacity` and then sizes its own request at half the
brain's stated capacity, so it decides for itself rather than being told.

The named fake win was "the second agent is a button in our own UI calling an internal
function". This is a standalone program with its own log and its own exit code.

## Result: 12 of 13 observable checks pass, DEMONSTRATED

Status codes observed in the regenerated log:

| count | outcome |
|---|---|
| 5 | 200 as expected (health, thesis, capacity, quote, accept) |
| 2 | 401 as expected (no API key, unknown API key) |
| 1 | 400 as expected (malformed JSON body) |
| 1 | 403 as expected (another caller tried to accept your quote) |
| 2 | 409 as expected (double-accept refused; size beyond risk capacity refused) |
| 1 | 410 as expected (expired quote refused) |
| 1 | 404 as expected (unknown endpoint) |

The 409 on an oversized request is the most important line: it came from the same
`RiskEngine::evaluate` the brain applies to itself, over HTTP, to a stranger.

## A real performance defect found and fixed

The first run failed three checks for one cause: every authenticated request performed
seven sequential chain reads costing seconds, so a 15 second quote expired before the
client's next request completed, and the 60 second rate window reset mid-burst so the
count could never accumulate. Fixed with a 2 second snapshot and guard-state cache that
reports its own age. After the fix, 12 of 13 pass.

## KNOWN LIMITATION, not fixed: the server stalls under a rapid burst

Reproduced twice. During the 40-request burst in section 9 the server stops responding
and the client fails with `TimeoutError`. The connection is accepted and then never
serviced, so the single request-handling thread is stuck rather than the process being
dead.

What was tried: per-socket read and write timeouts of 3 seconds, on the theory that a
slow or half-open client was parked in `read_line`. That did NOT resolve it, so the
diagnosis was wrong and the cause is still open.

Consequence, stated plainly:
- The rate limiter's 429 path has therefore never been OBSERVED tripping. It is
  implemented and unit-reachable but not demonstrated. Marked INFERRED, not
  DEMONSTRATED.
- A sustained burst against this endpoint is a denial of service with no attacker
  sophistication required.

The stated remedy, deliberately not attempted at this point in the schedule: give each
connection its own thread and put `State` behind a `Mutex`. That is the correct design
for a stranger-facing server and is roughly a thirty line change. It was deprioritised
because Phase 7 and Phase 8 were unbuilt at the time, and an absent deliverable costs
more than a disclosed limitation. Recorded here rather than left as a surprise.

## Not claimed

- No settlement through this endpoint. `/accept` records acceptance; the brain runtime
  performs settlement. The response says so.
- Auth is by API key, not wallet signature. The operator has no browser wallet and a
  signature scheme adds dependency without adding safety at this scope. See ADR-010.
- Demo API keys are hardcoded. Fine for a testnet demo, stated rather than implied.
