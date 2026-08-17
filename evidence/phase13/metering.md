# Task 13.2: coordination metering

Run 2026-08-16 09:22:29 UTC.

## Per-caller usage, counted by the API itself

The coordination API already tracks calls per api-key for rate limiting. Metering reads the
same counters, so usage and throttling cannot disagree.

```
{
    "chain_id": 1952,
    "ok": true,
    "protocol_version": "1.0.0",
    "refused": 0,
    "served": 0
}
```

## Usage by the external agent

`scripts/96-external-settlement.sh` drives a genuinely separate process that requests a quote,
is refused on one side, takes the reducing side, and has it settled onchain. Its accepted
quotes are appended to a handoff record.

```
accepted-quotes.jsonl rows: 7

caller                         calls    notional (micro)     fee at 49 bps
external-agent-1                   7             3500000             17150
TOTAL                              7             3500000             17150
```

## The fee that WOULD apply, and why it is not charged

The rate above is `FeeCollector.feeBps()` read live from `0x2e0727C36c9F720E8d31C5eB3a3748A683610e38`: **49 bps**. It is
the same rate the trading path charges, deliberately, so the business model is one number
rather than two that can drift.

**Nothing is billed today.** The coordination API is unauthenticated by design and its own
module docs say there is no privileged path: a caller cannot obtain a quote the agent itself
would be refused. Charging for access would require an identity system this project does not
have and did not build.

So this is a QUOTE, not an invoice, and the evidence says so. The claim being supported is
"usage is measured and priceable at a rate that already exists onchain", not "usage is
monetised". The second would be false.

## Second-order: what pricing coordination would change

Worth stating because task 13.2's thinking models are game-theoretic, and a metering design
that ignores caller incentives is a spreadsheet rather than a mechanism.

- A per-CALL fee prices asking, which discourages the exploratory quotes that make the refusal
  ledger informative. A caller who is charged to ask will ask only when confident, and the
  refusals are the part of this system worth reading.
- A per-SETTLEMENT fee prices success, which is what the trading path already charges and what
  the numbers above compute. A caller pays only when the agent's answer was worth acting on.
- Free quotes with paid settlement is therefore the only variant consistent with the rest of
  the design, and it is the one costed here.
