# ADR-010: API-key auth for the coordination surface, not wallet signatures

Date 9 Aug 2026. Status ACCEPTED. Referenced by `crates/coordination-api/src/main.rs`.

## Context

The coordination API lets an external agent request a quote, query risk capacity, and read
the brain's thesis. It needs to identify callers, because a quote is a short-lived option
written to whoever asked for it and per-caller rate limits are meaningless without identity.

Two obvious options: sign requests with an Ethereum key and recover the address, or issue API
keys.

## Decision

API keys in an `x-api-key` header. Two demo keys mapped to two caller identities so
per-caller behaviour is observable.

## Why not wallet signatures

1. **The operator has no browser wallet and does not intend to install one.** Every path in
   this project is CLI or pasted-address for that reason. A signature scheme would push the
   same requirement onto every caller.
2. **It would add safety that is not needed at this scope.** Signatures would prove control
   of an address. Nothing in this API cares about an address: quotes are not bearer
   instruments, settlement is performed by the brain runtime rather than by the caller, and
   `/accept` records acceptance rather than moving funds. Authentication here answers "which
   quota bucket is this" and nothing more.
3. **It would add a dependency and a replay-protection design** (nonces, domain separation,
   expiry) to a surface whose real risk is a burst, not impersonation.

## Why not open and unauthenticated

An unauthenticated `/quote` endpoint is a free option written to the internet, and it reveals
the agent's book view and remaining risk capacity. Rate limits cannot exist without identity.

## Consequences, stated plainly

- **Demo keys are hardcoded** in the binary. Fine for a testnet demo, wrong for anything
  else. Real deployment needs keys out of the source and per-caller quotas that an operator
  can change without a rebuild.
- API keys travel in cleartext over HTTP on localhost. Public deployment requires TLS.
- Keys identify a quota bucket, not a legal counterparty. Nothing in this design supports
  settlement obligations against a named party.

## What this does NOT weaken

Authentication is not a security boundary for the money. The boundary is the risk gate:
every external request passes through the same `RiskEngine::evaluate` the brain applies to
itself, so a caller with a valid key still cannot obtain a quote the agent would be refused.
That was demonstrated live, with an oversized request returning 409 from the risk gate rather
than from any auth check.

## Revisit when

Settlement moves to the caller, quotes become transferable, or the endpoint is exposed
publicly. At that point signatures stop being ceremony and start carrying weight, and the
replay-protection design has to be done properly rather than bolted on.
