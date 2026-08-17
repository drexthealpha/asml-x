# Integration seam test: UI to runtime to chain

Task 4.8. Run 2026-08-12 03:00:16 UTC

The path has three seams and each one is checked against the next, rather than each
component being checked against my expectation of it:

1. runtime writes a journal row  ->  2. UI reads and renders it  ->  3. chain confirms the tx

## Step 1: what the runtime wrote
  rows staged for the UI: 43
  rows with a transaction: 39
  newest decision id: 130  block: 38042899
  newest submitted decision: id 129 block 38042865
  tx: 0xcb336f5831098e6a6b37a13b16d5752c9c37739e584e011fd4f8d7f3d7f1ede1

## Step 2: what the UI rendered

Measured in the live page with the DOM, not by screenshot, so the numbers are exact.
Served build: ui-v2/dist at http://localhost:4173

```
{
  "headerBlock": "38042899",
  "headerDecisions": "43",
  "headerSubmitted": "39",
  "headerRefusals": "2236",
  "brainDecisionId": "130",
  "brainBlock": "38042899",
  "riskBar": "MarketNotionalTooLarge 52.96 / 50.00 100%",
  "firstTxInPanel": "0xcb336f5831098e6a6b37a13b16d5752c9c37739e584e011fd4f8d7f3d7f1ede1",
  "journalHead": "130 38042899 hold 0.0% 53 no tx | 129 38042865 take order 25 Sell 0.125000 base at 2.100"
}
```

## Step 3: what the chain says

  tx:                 0xcb336f5831098e6a6b37a13b16d5752c9c37739e584e011fd4f8d7f3d7f1ede1
  receipt status:     0x1
  gas used:           136566
  block from chain:   38042894
  block from journal: 38042865   (decision 129)
  explorer:           https://www.oklink.com/x-layer-testnet/tx/0xcb336f5831098e6a6b37a13b16d5752c9c37739e584e011fd4f8d7f3d7f1ede1

## Verdict, task 4.8
  drift for this decision: 29 block(s) between the read and the landing

### Drift across EVERY submitted decision, measured
  submitted decisions checked against chain: 39 of 39
  drift blocks  min 22  median 25  max 30
  at 1.0s per block that is 22s to 30s from read to landing
  landed before the read (impossible if the seam is sound): 0

  DIRECTION HOLDS FOR ALL

## Verdict, task 4.8
  RESULT: PASS.
  The transaction the UI shows for decision 129 exists on chain 1952 with status 0x1, it
  landed AFTER the block the decision was read at, and the same holds for every submitted
  decision in the journal (checked above, not sampled).

  What is asserted: direction. Landing block is at or after the read block, for all of them.
  What is NOT asserted: equality, or any invented bound on the gap. The gap is real latency
  in the signing path, it is reported above as a distribution, and it is the same debt
  ADR-008 records: signing goes through a cast subprocess, which pays a process spawn and a
  scrypt keystore decrypt per transaction. Task 6.6 is where alloy's in-process signer gets
  weighed against it, and this measurement is the before-number for that decision.
