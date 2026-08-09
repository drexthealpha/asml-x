# ADR-001: the venue is ours

Date 9 Aug 2026. Status ACCEPTED. Supersedes nothing.

## Context
The spec assumes Exchange OS primitives (matching, margining, liquidation,
settlement) are available to build against. Four primary probes say they are not.
See docs/verified/exchangeos-availability.md. The approved fallback was a hybrid:
a real third-party DEX for spot and perps, own contracts for outcome and RWA.

## Decision
Deploy our own minimal venue contracts on chain 1952 as the execution substrate
for every vertical. Label them plainly as self-deployed in UI, README, and demo.

## Why the hybrid collapsed
No Uniswap V2 or V3 factory, router, or position manager at any canonical
address. 300 sampled blocks contained 110 real user transactions across 7 distinct
contracts. There is no venue with liquidity to integrate against. Leg one of the
hybrid has no substrate, so the hybrid is its second leg in full.

## Cost, stated not hidden
Venue-level Exchange OS integration cannot be demonstrated. The "integration with
X Layer" criterion rests instead on real deploys, real transactions, OP Stack
predeploy use, and Multicall3. A judge could read a self-deployed venue as
self-dealing, which the honesty framing in ADR-002 is designed to pre-empt.

## What it preserves
Every transaction remains real, onchain, and explorer-verifiable. R6 holds fully.
