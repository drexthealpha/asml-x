# ADR-012: no LLM agent framework on the decision path

Task 1.17. Status: ACCEPTED. Date: 2026-08-11.

THINKING: #11 second-order (a framework choice propagates into every later phase and is the
most expensive thing to reverse), #23 systems (the question is where a framework would sit in
the existing process boundary, not which framework is best in the abstract), #3 first
principles (what does the coordination path actually need to do), #61 circle of competence
(these frameworks are Python or TypeScript and the brain is Rust, so adoption means a process
boundary, and the boundary's location is the whole decision).

## The candidates, evaluated

Product spec section 5 names five: elizaOS, LangGraph, AutoGen, CrewAI, MetaGPT. The Rust
side of the ecosystem was also surveyed, because the brain is Rust and a same-language option
would avoid the boundary entirely.

| framework | language | orchestration model | why it is not on the decision path |
|---|---|---|---|
| LangGraph | Python | directed graph, conditional edges, explicit state | The strongest candidate and the one with the largest production footprint in 2026. Rejected on the boundary argument below, not on quality. |
| AutoGen | Python | conversational GroupChat, multi-agent debate | Debate and consensus among LLM speakers. This agent's decisions are not produced by discussion, they are produced by a deterministic scoring function over signals. |
| CrewAI | Python | role-based crews, process types | Best prototype ergonomics, weakest production observability of the three. Nothing here is a prototype. |
| MetaGPT | Python | SOP-driven software-company roles | Aimed at generating software artifacts, a different problem. |
| elizaOS | TypeScript | plugin/character runtime for social agents | Built around a social presence and plugin actions. The venue interaction here is a signed transaction under a risk seal, not a character action. |
| Rig (rig-core) | Rust | unified provider API, typed tools, RAG | The one option with no process boundary. Genuinely tempting. Still rejected, reason below. |

Sources consulted: https://rig.rs/ , the 2026 multi-agent orchestration comparisons at
presenc.ai/research/multi-agent-orchestration-frameworks-2026 and
tensoria.fr/en/blog/multi-agent-orchestration-comparison , and
github.com/yarenty/kowalski for the Rust-native survey.

## The decision

No agent framework sits on the decision path. The coordination surface stays what it is
today: an explicit HTTP protocol in `crates/coordination-api/src/main.rs`, standard library
only.

## Why, in one sentence that can be checked

Every framework above orchestrates LLM calls, and there is no LLM call on this agent's
decision path, so a framework would be orchestrating nothing.

## Why, expanded

The decision path is: read a market snapshot, compute signals, score candidate actions, pass
the winner through the risk engine, receive a `RiskApproved<OrderIntent>` or a refusal, sign,
submit. Locate the LLM in that sequence. There is none. Scoring is integer arithmetic in
`crates/decision-engine/src/lib.rs:289` (`score_take`); the seal is a Rust type at
`crates/risk-engine/src/lib.rs:251` (`RiskApproved`, with `_seal`, private, at :256).

That type is the reason the boundary argument is decisive rather than stylistic.
`RiskApproved<T>` cannot be constructed outside `risk-engine`. Forging one is a COMPILE error,
which is a stronger guarantee than any runtime check, and it is the single strongest safety
claim in this project. A Python orchestrator would have to cross a process boundary at exactly
the point where that seal is enforced. On the far side of a JSON boundary, `RiskApproved` is a
dict. The compile-time guarantee degrades into a runtime convention, which is what it was
specifically built not to be.

Rig deserves the separate answer, since it is Rust and the boundary objection does not apply.
It is rejected for the plainer reason: it is a library for building LLM applications, and this
agent's decisions contain no LLM step. Adopting it would mean adding a provider abstraction,
a tool-calling layer and a RAG surface that nothing in the decision path calls. It would show
up in `Cargo.toml` and nowhere else.

## What is genuinely lost, stated rather than confessed

Per R-NO-CONFESSION this section exists to record what was BUILT in place of each framework
feature, not to advertise a gap.

1. Graph-structured retries and resumable state, LangGraph's real strength. Built here
   instead: the journal at `crates/journal` is append-only and every decision is replayable
   from it, which is the property that mattered. Evidence: `evidence/journal.jsonl`, 87 rows,
   and the river benchmark in task 1.14 reads them as a dataset, which only works because the
   record is complete.
2. Built-in observability and tracing. Task 6.8 adds tracing plus OpenTelemetry directly.
   This is a dependency, not a framework.
3. Human-in-the-loop interrupts. Already present and stronger: `RiskApproved` carries
   `requires_human_approval` (`crates/risk-engine/src/lib.rs:274`), so the escalation is part
   of the sealed value the executor must inspect, not a framework callback that can be
   forgotten.
4. Multi-agent debate, AutoGen's distinctive capability. Deliberately absent. Consensus among
   speakers is a way to get a defensible answer when there is no ground truth. Here there is
   ground truth: the risk engine either approves or refuses, and a debate that could talk its
   way past a refusal would be a defect.

## Where a framework IS still allowed

Off the decision path, an external agent in any language may call the coordination API. That
is the point of it being HTTP. A LangGraph or elizaOS agent can request a quote, and it will
pass the SAME risk gate as an internal decision, with the same expiry and the same rate limit
(`crates/coordination-api/src/main.rs:9-19`, `rate_ok` at :126). Nothing about this ADR closes
that door; it fixes which side of the door the seal lives on.

## Falsification test

This ADR is wrong if an LLM call ever appears on the decision path between snapshot and
signature. If that happens, orchestration becomes a real problem and LangGraph becomes the
right answer for it. The test is mechanical: `crates/decision-engine`, `crates/risk-engine`
and `crates/executor` must contain no HTTP client and no model provider dependency. Check with
`grep -rn "reqwest\|openai\|anthropic\|gemini" crates/{decision-engine,risk-engine,executor}/`.
An empty result keeps this decision valid.
