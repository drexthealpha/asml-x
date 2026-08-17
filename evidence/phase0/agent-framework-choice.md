# Agent framework choice, task 1.17

Evidence path named in TASKS.md 1.17. The full reasoning is ADR-012
(`docs/decisions/ADR-012-agent-framework.md`); this file records the comparison and the
verification that the choice is real rather than asserted.

Reproduce the falsification test:
`grep -rn "reqwest\|openai\|anthropic\|gemini" crates/decision-engine crates/risk-engine crates/executor`
Result on 2026-08-11: EMPTY. No HTTP client and no model provider on the decision path.

## R-SEARCH-1 verification, current state as of Aug 2026

Searched rather than recalled, since framework positioning is exactly the fast-changing kind of
fact the rule names.

| framework | current state | source |
|---|---|---|
| LangGraph | Largest production footprint in 2026; directed graph with conditional edges, explicit state management. The reference choice for enterprise multi-agent. | presenc.ai/research/multi-agent-orchestration-frameworks-2026 , tensoria.fr/en/blog/multi-agent-orchestration-comparison |
| CrewAI | Strongest demo-to-prototype ergonomics; trails on production observability and error recovery. | same |
| AutoGen | Leads research and academic adoption, mature multi-agent debate and verification patterns; smaller production adoption. | same |
| MetaGPT | SOP-driven software-company roles, aimed at generating software artifacts. | ecosystem surveys above |
| elizaOS | TypeScript plugin/character runtime for social and Web3 agents. | project docs |
| Rig (rig-core) | ~6.7k stars, unified API across 20+ providers, typed tools, RAG; most CPU-efficient in the 2026 cross-language benchmark. | rig.rs |

## The choice

**None on the decision path.** Coordination remains the explicit HTTP protocol in
`crates/coordination-api/src/main.rs`, standard library only.

TASKS.md 1.17 asked for ONE to be chosen and justified against the others. The honest answer
after the comparison is that the premise does not hold here, and the reason is checkable rather
than rhetorical: every framework listed orchestrates LLM calls, and there is no LLM call
between market snapshot and signature. Naming a winner anyway would produce exactly the fake
win 1.17 warns about, an import that never transacts. The counter-test 1.17 sets is that the
chosen framework must complete a real quote-accept-settle cycle in 6.4. That test is preserved,
not dodged: 6.4 still requires an EXTERNAL agent to complete the cycle against the live API,
and the API is HTTP precisely so that agent can be written in any framework a caller likes.
What changes is which side of the process boundary holds the risk seal.

The decisive technical fact, verified above: `RiskApproved<T>`
(`crates/risk-engine/src/lib.rs:251`, with a private `_seal` field at :256) cannot be
constructed outside `risk-engine`. Forging one is a compile error. Across a JSON boundary it is
a dict, and the compile-time guarantee becomes a runtime convention.

## Recorded as evaluated-not-used

All six rows above are in `evidence/TOOL-USAGE.md` under EVALUATED-REJECTED with the specific
reason per framework, not a shared boilerplate line.

## What was built instead of each framework feature

Listed in ADR-012 with the artifact for each: append-only journal for replay (87 rows,
readable as a dataset, which is what proves the record is complete), tracing plus
OpenTelemetry in 6.8 as a dependency rather than a framework, and human-in-the-loop as
`requires_human_approval` carried inside the sealed value at
`crates/risk-engine/src/lib.rs:274` rather than as a framework callback that can be forgotten.
