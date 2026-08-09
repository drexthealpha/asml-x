# Exchange OS availability on X Layer testnet

Verified 9 Aug 2026. Task 0.3.2, 0.3.3. This is the Phase 2 gate.

## Finding

Exchange OS has NO public developer surface on X Layer testnet as of this date.

Status: DEMONSTRATED (four independent primary probes below, all negative).

## Evidence

1. Official Exchange OS whitepaper V1.0, May 2026, fetched from
   `https://web3.okx.com/whitepaper/okx-exchange-os.pdf`, 23 pages, 33,420 chars.
   Local copy: `evidence/exchangeos-recon/okx-exchange-os.pdf`.
   - Ethereum addresses in document: **0**
   - Occurrences of "testnet": **0**
   - Occurrences of "API": **1**
   - Occurrences of TradeZone 11, matching 17, margin 21, outcome 17,
     settlement 12. So the document is architectural, not integrational. It
     describes a design, not a callable surface.

2. X Layer developer documentation navigation, fetched live from the Onchain OS
   dev-docs tree, 59,796 bytes. Occurrences of "Exchange OS", "TradeZone",
   "venue", "order book", "outcome market" in the developer nav: **0**. One
   incidental "perpetual". There is no Exchange OS developer section to read.

3. Candidate TradeZone RPC hostnames probed, all NXDOMAIN. These hostnames were
   guesses, so this is weak corroboration, not proof. Recorded as weak.

4. Press coverage states external-builder venue deployment is "scheduled for
   Q3 2026 through the XIP-Exchange OS governance process", and the first venue
   (2026 World Cup Outcomes) was a simulated market run by X Layer itself, not an
   open developer environment.

## Consequence for the spec

The specification's core requires "direct native use of Exchange OS primitives
(matching, margining, liquidation, settlement)" and treating "Exchange OS spot,
perps, and outcome markets as one coherent system". That cannot be built against
reality today. Any code claiming to integrate Exchange OS on testnet right now
would be a mock behind a clean interface, which standing rules R6 and R9 forbid
and which the reverse-reward-hacking mandate names explicitly as a fake win.

## What is real and available on chain 1952

- The chain itself: verified, chain ID 1952, blocks producing at roughly 0.8s,
  gas price 20,000,001 wei, deploys and transactions confirmed working.
  See `evidence/first-tx.md`.

## Options

A. Run the brain against a real third-party venue already live on chain 1952.
   Real contracts, real fills, fully provable. Exchange OS becomes a documented
   migration target rather than a claim.
B. Deploy our own minimal order-book and outcome-market contracts on chain 1952,
   labelled plainly as a stand-in for Exchange OS primitives. Fully real onchain,
   but the venue is ours, so "deep Exchange OS integration" is not demonstrable.
C. Seek Exchange OS testnet access through XIP governance. Unbounded latency,
   incompatible with a 21 Aug deadline.
D. Hybrid: A for spot and perps reality, B for the outcome-market and RWA
   vertical that A will not cover.

Recommendation: D, with A attempted first, and every Exchange OS claim in the
README and UI labelled INFERRED with this file as the reason.
