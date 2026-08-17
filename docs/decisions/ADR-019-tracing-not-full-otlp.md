# ADR-019: real OpenTelemetry SDK with the stdout exporter

Status: **SUPERSEDED BY ITSELF, 2026-08-16.** The first version of this ADR decided against the
OpenTelemetry SDK on a factual claim that was never tested and turns out to be false. This version
records the correction and the decision actually in force. Task 14.3.

## The claim that was wrong

The original ADR rejected `opentelemetry` on two grounds. The second was:

> **`opentelemetry-otlp` is not in the local cargo cache.** This machine cannot reach crates.io
> reliably (E9 covers the general pattern), so adding it risks a build that works here and fails on
> a clean clone.

**Not true, and one command shows it.** E9 records that `okx.com` and
`generativelanguage.googleapis.com` are blocked by this machine's resolver. That is a fact about two
specific hosts. I generalised it into "the network is unreliable" and used the generalisation to
justify not trying. The measurement:

```
https://crates.io/            403     Cloudflare refusing a bare curl, a host cargo never contacts
https://index.crates.io/      200     the sparse registry index cargo actually reads
https://static.crates.io/     200     the crate download host
```

Then:

```
cargo add opentelemetry opentelemetry_sdk opentelemetry-stdout
  Adding opentelemetry v0.32.0
  Adding opentelemetry_sdk v0.32.1
  Adding opentelemetry-stdout v0.32.0
```

It resolved and built first try. The 403 I would have seen had I looked is on the web frontend, which
is not part of cargo's fetch path at all.

**The rule broken was R-SEARCH-1: verify anything external before building on it.** An ADR is the
worst place to put an untested environment claim, because an ADR is where a later reader goes to find
out whether a question is settled. This one would have told them the door was locked without anybody
having tried the handle. Same failure shape as ADR-018, where a mobile-layout emergency turned out to
be my own measurement code ignoring scroll clipping.

## The claim that was true and still did not support the conclusion

> **It needs infrastructure this submission cannot ship.** A collector is another process, another
> port, another thing a judge must start.

True of `opentelemetry-otlp` over gRPC, and it argues against **that exporter**, not against the SDK.
The SDK's exporter is a trait. `opentelemetry-stdout` implements it with no collector, no port and no
second process. Rejecting the whole library because one of its exporters needs infrastructure was a
scope error: I judged the dependency by its heaviest configuration.

## Decision now in force

Use the real OpenTelemetry SDK: `opentelemetry` 0.32, `opentelemetry_sdk` 0.32 and
`opentelemetry-stdout` 0.32.

- Trace ids, span ids and parent-child linkage come from `SdkTracerProvider` and OpenTelemetry's own
  `Context`. They are the specification's identifiers, not this repo's. That is the substantive gain
  over the hand-rolled version, which minted its own ids and could only ever be OTLP-*shaped*.
- The stdout exporter writes real OpenTelemetry span output, proving the SDK is genuinely wired.
- A parallel JSON-lines file at `evidence/phase14/decision-trace.jsonl` is what the gate asserts on
  and what `jq` reads. Two sinks on purpose: asserting against the SDK's human-oriented stdout format
  would mean asserting against a format its authors are free to change between minor versions.
- Durations are taken from `Instant`, which is monotonic, so a wall clock stepping backwards mid-run
  cannot produce a negative duration in the evidence.

## What is claimed, and what is not

**Claimed:** one decision traced end to end through the real OpenTelemetry Rust SDK, with a span per
stage, SDK-assigned parent-child structure and per-stage timings, reproducible from a clean clone with
one script and no extra infrastructure.

**NOT claimed:** an OTLP-over-gRPC exporter, a running collector, or Jaeger integration. Adding
`opentelemetry-otlp` is now a pipeline-construction change of a few lines and nothing else, since the
spans, their names and their attributes do not move. It is not done here only because there is no
collector to point it at, and a trace that needs one to read is a trace nobody reads.

## Rule this leaves behind

**Do not put an untested external fact in an ADR.** If a claim about the environment can be checked
by one command, run the command before writing the ADR that depends on it. If it cannot be checked,
write down that it is unverified, in those words.
