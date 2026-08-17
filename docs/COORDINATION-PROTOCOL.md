# Coordination protocol 1.0.0

For other builders integrating with the ASML-X coordination API. Generated
2026-08-16 19:15:42 UTC by `bash scripts/179-protocol-version.sh`, which probes a
live server and writes this file from the responses it got.

**The shapes below are captured, not remembered.** A protocol note that drifts from its server
is worse than no note, because another team writes code against it and then debugs their own
client. The compatibility rules further down are the only hand-written part, because no probe
can discover them.

## Version and where to read it

`GET /health` returns `protocol_version`, currently **1.0.0**. It requires no API key, so a
client can check compatibility before authenticating.

## Endpoints

| method | path | key | purpose |
|---|---|---|---|
| GET | `/health` | no | liveness, chain id, protocol version, served and refused counts |
| GET | `/thesis` | yes | the current market thesis and its signals |
| GET | `/capacity` | yes | what the agent can still take on |
| POST | `/quote` | yes | request a price for a size and side |
| POST | `/accept` | yes | accept a quote you were given |

Authentication is the `x-api-key` header. Everything except `/health` returns 401 without it.

## Live responses from this run

```
== GET /health (no key required) ==
{"chain_id":1952,"ok":true,"protocol_version":"1.0.0","refused":0,"served":0}

== GET /thesis ==
{"block":38448865,"confidence_bps":0,"halted":false,"imbalance_bps":"-3928","live_orders":25,"market":"tBASE/tQUOTE","snapshot_age_ms":817,"spread_bps":"-6666","thesis":"BOOK IS CROSSED: best bid 2.400000 is at or above best ask 1.200000, so spread-based inference is unreliable; spread -6666 bps observed, volatility not yet estimable, fewer than three mid observations so far; depth is ask-heavy by 3928 bps"}

== GET /capacity ==
{"current_exposure_micro":"23456250","first_refusal_beyond":null,"halted":false,"max_permitted_size_micro":"12500000"}

== POST /quote ==
{"block":38448865,"expires_at_ms":1786907757513,"market":"tBASE/tQUOTE","price_micro":"1200000","quote_id":1,"requires_human_approval":false,"side":"Buy","size_micro":"250000","ttl_ms":15000}


== POST /accept ==
{"accepted":true,"handoff_error":null,"handoff_written":true,"held_ms":41,"market":"tBASE/tQUOTE","note":"queued for settlement by the brain runtime, which owns the keystore; this endpoint never signs","price_micro":"1200000","priced_at_block":38448865,"quote_id":1,"side":"Buy","size_micro":"250000"}

== refusals a client must handle ==
```

## Refusals a client must handle

```
== refusals a client must handle ==
  no api key on /thesis:        401
  unknown quote_id on /accept:  404
  size_micro as a number:       400
  unknown endpoint:             404
```

Every refusal is a JSON object with an `error` string. **A client should never parse the HTTP
status alone**: 409 on `/quote` means there was no reference price on that side, which is a
market condition and worth retrying, while 400 means the request was malformed and never will
be. Same class of code, opposite correct behaviour.

## Compatibility rules

This is the part a version number is for. Under `1.0.0`:

1. **`size_micro` is a STRING, not a number.** It is an `i128` in micro units, and JSON numbers
   are IEEE 754 doubles in most clients, which silently lose precision above 2^53. A numeric
   `size_micro` is refused with 400 rather than accepted and rounded. Refusing beats a quiet
   wrong answer.
2. **A quote belongs to the caller who requested it.** Accepting another caller's quote_id
   returns 403, not 404, so a client can tell "not yours" from "does not exist".
3. **Quotes expire.** A quote not accepted within its validity window is refused on accept. Do
   not cache them.
4. **Unknown response fields must be ignored, not rejected.** New fields may be added within a
   minor version. A client that fails on an unrecognised key will break on an addition that is
   compatible by this document's own definition.
5. **Field removals, type changes and status-code meaning changes are MAJOR.** They will not
   happen inside `1.x`.
6. **The fee is quoted, not charged, by this API.** `/quote` prices a usage fee, and the API is
   unauthenticated in any billing sense: there is no identity system behind the API key. Do not
   build settlement on the assumption that a quote creates an obligation.

## What this API is NOT

Stated so nobody integrates against a promise that was never made.

- **Not a venue.** Accepting a quote records an intent; it does not execute your trade.
- **Not multi-market.** Every endpoint answers for `tBASE/tQUOTE` on chain 1952, against a
  self-deployed stand-in venue.
- **Not authenticated per identity.** The API key selects a rate-limit bucket. It is not a
  user account and nothing is billed to it.
- **Not rate-limit-free.** The limiter returns 429. It was raised to 500 for this probe so it
  would not mask the other refusals; its own demonstration is in
  `evidence/phase6/rate-limit-429.txt`.

## Reproduce

```
bash scripts/179-protocol-version.sh
```
