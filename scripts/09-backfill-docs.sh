#!/usr/bin/env bash
# Backfill the five decisions into docs/decisions/ and create the R18 checkpoint
# ledger. Cheaper as one script than as many separate file writes.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
D="$REPO/docs/decisions"
mkdir -p "$D" "$REPO/evidence/gates"

cat > "$D/ADR-001-venue-strategy.md" <<'MD'
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
MD

cat > "$D/ADR-002-exchange-os-claims.md" <<'MD'
# ADR-002: Exchange OS is a migration target, not a claim

Date 9 Aug 2026. Status ACCEPTED.

## Decision
Every Exchange OS mention in README, docs, UI, and pitch becomes a labelled
INFERRED forward claim citing docs/verified/exchangeos-availability.md. The live
demo makes no Exchange OS claim at all.

## Why
Claiming integration with a surface that has no testnet presence would be the
exact fake win the reverse-reward-hacking mandate names: a mock behind a clean
interface. R6 and R9 forbid it.

## Cost
Weaker differentiation than the spec intended. Full defensibility under scrutiny,
which is worth more than a claim that collapses when a judge checks.
MD

cat > "$D/ADR-003-testnet-only.md" <<'MD'
# ADR-003: testnet only, zero cash

Date 9 Aug 2026. Status ACCEPTED. User instruction.

## Decision
No mainnet deployment, no bridging, no real funds, zero cash cost. Task 10.1.x
collapses to writing docs/mainnet-path.md as a forward commitment with real
migration steps and dates, and stating plainly in README and judge guide that the
submission is testnet with a documented mainnet path.

## Consequence
Do not spend time verifying whether mainnet is required by submission. The rule
text reads "subsequently launched on X Layer mainnet", which is a forward
commitment. Stated as INFERRED from the rule wording.
MD

cat > "$D/ADR-004-grounding-substitution.md" <<'MD'
# ADR-004: gemini-grounding substituted

Date 9 Aug 2026. Status ACCEPTED.

## Context
R14 requires a freshness check through gemini-grounding before confirming against
a primary source.

## What happened
One test query to the native generateContent endpoint with the google_search tool
returned a transport failure: SSL_read unexpected eof from
generativelanguage.googleapis.com. Same interference pattern as this machine's
okx.com DNS block. Per instruction and R17, not investigated.

## Decision
R14's freshness step is WebSearch plus the DoH-pinned direct fetch implemented in
scripts/lib.sh. That combination produced every verified finding so far, including
the chain ID 1952 correction and the OP Stack determination.

## Honesty note
Recorded as "unreachable from this network", NOT as "no free quota". The quota
question was never answered, and claiming otherwise would be an unevidenced claim.
MD

cat > "$D/ADR-005-no-floats-no-clocks.md" <<'MD'
# ADR-005: integer micro-units, time as an argument

Date 9 Aug 2026. Status ACCEPTED.

## Decision
The risk engine and all shared value types use integer micro-units (1e6 scale) and
never read a clock. Time is passed in. float_arithmetic is denied at the workspace
lint level and unsafe_code is forbidden.

## Why
Two reasons, both about provability. Floats make invariants unprovable and
introduce rounding an adversary can steer. A function that reads a clock cannot be
symbolically executed or exhaustively tested. Phase 3 formal verification depends
on both properties holding from the start, and retrofitting them later would mean
rewriting the engine.

## Cost
All arithmetic must scale carefully. The micro-squared divisor in notional lives in
exactly one place (OrderIntent::notional_micro) because that is the classic
fixed-point bug. A mutation test covers it.
MD

cat > "$REPO/evidence/checkpoints.md" <<'MD'
# Checkpoint ledger

R18 forbids git tags, so this file is the audit trail instead. One line per
checkpoint: name, UTC time, what was proven, evidence path.

| checkpoint | UTC | proven | evidence |
|---|---|---|---|
MD

printf '| CHECKPOINT-0 | %s | Chain 1952 live, wallet funded, first real deploy and tx landed with explorer links | evidence/first-tx.md |\n' \
  "$(date -u '+%Y-%m-%d %H:%M')" >> "$REPO/evidence/checkpoints.md"
printf '| CHECKPOINT-1-RECON | %s | OP Stack determination from bytecode, chain activity scan, Exchange OS absence established from primary sources | docs/verified/chain-1952-reality.md |\n' \
  "$(date -u '+%Y-%m-%d %H:%M')" >> "$REPO/evidence/checkpoints.md"
printf '| CHECKPOINT-2.1 | %s | Risk engine: 16 tests green, 14/14 mutations RED, forging RiskApproved fails to compile | evidence/mutation-risk-engine.md |\n' \
  "$(date -u '+%Y-%m-%d %H:%M')" >> "$REPO/evidence/checkpoints.md"

echo "written:"
ls -1 "$D"
echo "and evidence/checkpoints.md"
