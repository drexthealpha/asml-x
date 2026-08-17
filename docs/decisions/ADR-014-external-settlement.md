# ADR-014: the coordination API never signs; the runtime settles

Task 6.4. Status: ACCEPTED. Date: 2026-08-13.

THINKING: #24 game theoretic (the caller is a stranger who may probe or lie), #29 margin of safety
(where the key lives decides the blast radius of every other bug on this surface), #11 second order
(the handoff shape decides whether a settlement can ever be traced to a request).

## Decision

`POST /accept` writes an append-only handoff record and returns. It does not sign, does not submit,
and holds no keystore. `asml settle-accepted` reads that file, re-runs the risk gate against the
CURRENT book, submits through the BatchExecutor, and writes the transaction hash back into both the
handoff record and the journal.

## Why the split

The coordination API is the surface strangers reach. It authenticates with a demo API key that is
hardcoded and documented as such. Putting a signer behind that would mean a key compromise, a parsing
bug, or a logic error on this endpoint is a spend, rather than a bad quote.

Keeping the key in the runtime means the worst an API compromise can do is enqueue a settlement that
the runtime will independently re-check and can refuse.

## The re-check is the load-bearing part

A quote prices a book that existed at a specific block. By the time settlement runs, the book has
moved. Settling on the strength of the quote alone would make the risk engine advisory on this path
while it is binding everywhere else.

Observed in the first end-to-end run, and this is why the re-check exists rather than being a
formality: `/capacity` offered 12,500,000 micro, the caller asked for a quarter of it, the quote was
issued, and the settlement re-check refused with
`MarketNotionalTooLarge { got: 56299998, limit: 50000000 }`.

## That refusal exposed a real inconsistency, now fixed

The two gates were evaluating different portfolios:

| | portfolio |
|---|---|
| coordination API | `Portfolio { free_margin: 1000 * MICRO, ..Default::default() }`, an EMPTY book |
| runtime settlement | `read_portfolio(...)`, including the real onchain exposure of 50.36 against a 50 cap |

So the API was quoting against a book with no positions while the market was already at its cap.
Every quote it issued in that state was a promise settlement would refuse, which is worse than
refusing at quote time: the caller does work, accepts, and finds out afterwards.

The API now builds the same single-position portfolio from the same `exposureOf` reading it already
takes. A quote and its settlement now differ only by the blocks between them.

## Two more defects the end-to-end run found

1. **The fill was not clamped to the order.** Settlement sent the caller's full size at the quoted
   price, and the batch reverted with `LegFailed(3, venue, ...)`. A maker with less remaining base
   than the request cannot fill it, and the settling price is the maker's rather than the quoted one.
   The fill is now `min(requested, order.remaining_base())` priced off the order, and the handoff
   record carries `filled_micro` and `fill_price_micro` so a partial fill is visible rather than
   silent.
2. **A quote is a bound, not a size guarantee.** The first successful settlement was a partial fill:
   500,000 micro requested, 125,000 available on order 31. That is recorded rather than smoothed over.

## Result

```
quote 1 from external-agent-1: Sell 500000 micro at 2400000
  partial fill: order 31 has 125000 micro left of the 500000 requested
  SETTLED tx 0x6e1d99ff225a728ba031d2d5f5d191788cd9e6ac2ad037c4554f75c35cc7e53a
```

Receipt status `0x1`. The journal entry carries `decision_id: 1`, the quote id, and names the caller,
so the transaction is traceable to the request that caused it rather than merely adjacent to it in
time.

## What is NOT claimed

**No agent framework was used.** ADR-012 records why none sits on this path: there is no LLM call
between snapshot and signature, so a framework would orchestrate nothing. TASKS.md 6.4 asks for the
external agent to be built on "the framework chosen in 1.17", and the honest answer is that 1.17 chose
none. The requirement behind the words is that a SEPARATE process, in a different language, can trade
against this brain through a published surface. That holds: the caller is a plain HTTP client, which
is the point of the surface being HTTP rather than a framework binding.

## Known limitation, stated rather than hidden

The settle pass is a manual operator step, not a daemon. A crash between `submit_take` returning a
hash and the handoff file being rewritten would leave a record marked unsettled, and a rerun would
submit it twice. Making it automatic without an idempotency key would turn that from a rare manual
recovery into a routine double-spend. The idempotency key belongs on the BatchExecutor, which is a
contract change, and it is not being made this close to the deadline.
