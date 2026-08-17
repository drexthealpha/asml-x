# TOOL USAGE LEDGER

Every tool and repo named in product spec section 5. Appended AS WORK HAPPENS, never
retrospectively, because a ledger written at the end is fiction.

## Status vocabulary, task 1.18

The original three values could not describe the real outcomes without lying by omission, so the
set is wider. Every row carries one of these AND a reason:

- **USED** produced a real artifact in a real task, with the artifact named.
- **INSTALLED** present and verified, no product use yet.
- **INSTALLED, NOT YET USED** present, and the row says which task will use it and why not sooner.
- **SUBSTITUTED** could not be installed; the four R-SEARCH-2 rungs are named and the lost
  capability is stated rather than minimised.
- **EVALUATED-REJECTED** examined and deliberately not adopted, with the specific reason for this
  build, not a shared boilerplate line.
- **NOT-INSTALLED** deliberate omission with a reason.
- **NOT USED, REASON STATED** listed in the product spec and deliberately not consulted. This value
  exists because writing PENDING for something that will never be picked up is a promise, and
  writing USED for a repository nobody read would be a lie.
- **DEFERRED** owned by a later task, with the task number and the reason the wait is correct.
- **DECIDED, NOT YET INSTALLED** the choice is made and recorded; the change belongs to a later task.
- **IN PROGRESS** running right now.
- **READ** consulted as a reference, not installed.
- **NONE, BY DECISION** the row's whole category was rejected, with an ADR.

**Zero rows are PENDING** as of task 1.18. Verify:
`grep -cE '^\| [^|]+ \| PENDING' evidence/TOOL-USAGE.md` returns 0.
Also runnable: `bash scripts/59-tool-ledger-check.sh`

## Formal verification and safety

| tool | status | task | what it produced | evidence |
|---|---|---|---|---|
| halmos 0.3.3 | USED | v1 P3/P5, 1.2 | 14 theorems across RiskGuard and RwaRiskGuard, injected violations caught. 1.2 replaced a stale 0.1.13 that the VERIFIED FACTS table had already claimed was 0.3.3 | evidence/formal/, evidence/phase0/halmos.txt |
| kontrol | SUBSTITUTED | 1.3 | Four R-SEARCH-2 rungs named; capability covered by halmos plus hevm | evidence/phase0/kontrol.txt, evidence/phase0/tool-substitutions.md |
| hevm 0.57.0 | USED | 1.4 | 5 independent symbolic theorems on RiskGuard, `prove_` prefix, from argotorg/hevm (ethereum/hevm is dead) | evidence/phase0/hevm.txt, contracts/test/HevmCapProofs.t.sol |
| act | SUBSTITUTED | 1.6 | Nix-only build, NO prebuilt release asset. Capability loss (spec language independent of Solidity, Rocq extraction) stated, not minimised. act's own strongest EVM backend is hevm, already driven directly | evidence/phase0/act.txt, evidence/phase0/tool-substitutions.md |
| scribble | USED | 1.5 | Cap invariant instrumented and PROVEN TO FIRE via a plain-vs-instrumented differential: the plain contract accepts 150, the instrumented one reverts | evidence/phase0/scribble.txt, contracts/test/ScribbleFire.t.sol |
| foundry | USED | v1 all phases | 50 tests, 4 invariant campaigns, all deploys | evidence/mutation-contracts.md |
| cargo-mutants 27.1.0 | USED | 1.7, 7.5 | FINAL: **91 caught, 0 survived**. First run: 57 caught, **37 SURVIVED**, 13 unviable, 0 timeouts. The survivors were the finding: no test pinned any limit BOUNDARY, no test used a book with existing exposure so the post-trade projection arithmetic was never exercised, the shipped `conservative_testnet` defaults were asserted nowhere, and `is_halted` had no test at all. 11 new tests written to kill them, all 35 risk-engine tests pass, re-mutation run recorded | evidence/phase0/cargo-mutants-risk-engine.txt, evidence/phase0/cargo-mutants-after.txt |

## Agent frameworks and multi-agent

| tool | status | task | what it produced | evidence |
|---|---|---|---|---|
| elizaOS | EVALUATED-REJECTED | 1.17 | TypeScript plugin/character runtime for social agents; venue interaction here is a signed tx under a risk seal, not a character action | docs/decisions/ADR-012-agent-framework.md |
| langgraph | EVALUATED-REJECTED | 1.17 | Strongest candidate, rejected on the process boundary: a Python orchestrator turns the compile-time `RiskApproved<T>` seal into a JSON dict | docs/decisions/ADR-012-agent-framework.md |
| autogen | EVALUATED-REJECTED | 1.17 | Multi-agent debate has no role where the risk engine supplies ground truth; a debate that could argue past a refusal would be a defect | docs/decisions/ADR-012-agent-framework.md |
| crewAI | EVALUATED-REJECTED | 1.17 | Prototype ergonomics, weakest production observability of the three | docs/decisions/ADR-012-agent-framework.md |
| MetaGPT | EVALUATED-REJECTED | 1.17 | SOP-driven software-generation roles, a different problem | docs/decisions/ADR-012-agent-framework.md |
| Rig (rig-core) | EVALUATED-REJECTED | 1.17 | The only same-language option, so the boundary objection does not apply. Rejected because there is no LLM call on the decision path for it to orchestrate | docs/decisions/ADR-012-agent-framework.md |
| (chosen framework) | NONE, BY DECISION | 1.17, 6.4 | No framework on the decision path. Coordination stays an explicit std-library-only HTTP protocol. Falsification test is mechanical and currently EMPTY: no HTTP client or model provider dependency in decision-engine, risk-engine or executor | docs/decisions/ADR-012-agent-framework.md |

## Onchain and execution

| tool | status | task | what it produced | evidence |
|---|---|---|---|---|
| alloy 2.3.0 | USED | 1.12, 6.6 | Made one eth_call (`RiskGuard.sumOfParts()`) at a PINNED block and returned bytes IDENTICAL to the hand-rolled client: `0x…8bd1971ed00f8000`, with alloy independently reporting chain id 1952. The CLAUDE.md pin of 1.7.3 was stale; 2.3.0 is current and MSRV is now 1.94.1. Cost recorded: 17m10s to compile with the `full` feature, pulling in a TLS stack including aws-lc-rs | evidence/phase0/alloy.txt |
| revm 42.0.1 | USED | 1.13, 7.6 | THREE independent sources agree on the cap-breach revert selector `0x3e2ed028`: the Solidity error signature, the LIVE deployed guard's eth_call revert data, and a local in-memory simulation, which also decodes attempted=608e18 and cap=500e18 out of the payload. Two real API facts learned: revm 42 enforces the EIP-7825 per-transaction gas cap of 2^24, and `transact_commit` commits nonces so a sequence must track them | evidence/phase0/revm.txt |
| Uniswap v4-core / v4-periphery | NOT-INSTALLED | 1.16 | Nothing in the product deploys a v4 hook. Read as a reference for pattern only. | evidence/phase0/tool-substitutions.md |
| safe-smart-account | NOT-INSTALLED | 1.16 | Nothing in the product deploys a Safe module. Reference only. | evidence/phase0/tool-substitutions.md |
| reth | NOT-INSTALLED | 1.16 | Nothing in the product runs a node. revm covers local execution. | evidence/phase0/tool-substitutions.md |
| ERC-4337 references | READ | v1 P1 | EntryPoint v0.6 and v0.7 confirmed live on chain 1952 during recon | docs/verified/chain-1952-reality.md |

## UI and frontend

| tool | status | task | what it produced | evidence |
|---|---|---|---|---|
| hypeterminal | USED | 3.1-3.7 | Cloned at pinned commit a61992ed and read: 517 files / 70389 lines in apps/terminal. Produced evidence/ui-study.md with 70 verified path:line citations across 20 files, plus ADR-013 recording what transfers (layout constants, two-layer tokens, 12px/16px data rows, height-derived row counts, rAF batching, staleness watchdog) and what does not (Base UI components, the WebSocket transport, SSR, Lingui) ALSO PORTED, after a scan found the hand-rolled layout clipping 6945px of content into a 466px box: their exact dark token values (globals.css:200-286), their column-label style, and their resizable workspace with a viewport-minus-chrome body height. Citing a pattern is not applying one, and for three of them it had not been applied. | evidence/ui-study.md, evidence/hypeterminal/, docs/decisions/ADR-013-ui-primitives.md |
| react-resizable-panels 4.6.0 | USED | 5.x | Their `ui/resizable.tsx` wrapper ported verbatim, pinned to the version THEY pin rather than the 4.12.2 latest so behaviour matches the product being copied. Replaced a flex-wrap layout that made ~93% of the Risk view unreachable | ui-v2/src/components/resizable.tsx, evidence/phase5/layout-ported.md |
| Wick | NOT USED, REASON STATED | 3.5 reference | Listed as a chart reference. Not consulted: the chart work is task 9.3 and no chart exists yet, so reading a chart reference now would produce notes nothing acts on. The study effort went into HypeTerminal's order book and data layer instead, which is what the panels built in Phase 4 actually needed | evidence/ui-study.md |
| strata-pro-crypto-ui | NOT USED, REASON STATED | 3.2 reference | Three secondary UI references for density. One primary reference read to 70 citations beats three read to none, and HypeTerminal is a production terminal while these are templates. Recorded as evaluated-not-read rather than implied | evidence/ui-study.md |
| tbt-paper-terminal | NOT USED, REASON STATED | 3.2 reference | Same reason as strata-pro-crypto-ui | evidence/ui-study.md |
| shadcn-fintech | NOT USED, REASON STATED | 3.2 reference | Same reason. ADR-013 settles the shadcn question on the primitive layer, which is the decision these references would have informed | docs/decisions/ADR-013-ui-primitives.md |
| shadcn/ui | INSTALLED, NOT YET USED | 1.15, 4.1 | Primitives decided in ADR-013 (shadcn layer, HypeTerminal density). The Phase 4 panels are hand-written against the token layer; a generated component rendered at default spacing is the specific failure this project is judged against | docs/decisions/ADR-013-ui-primitives.md |
| lightweight-charts 5.2.0 | INSTALLED | 1.15, 9.3 | Pinned and verified in the lockfile. No chart is drawn yet: task 9.3 owns it, and a placeholder chart is a named failure condition | evidence/phase0/frontend-stack.txt |
| TanStack Table 8.21.3 | INSTALLED | 1.15, 4.4 | Pinned at 8.21.3 while 9.1.2 is current. Independently confirmed as the right pin: HypeTerminal's own apps/terminal/package.json pins the same version | evidence/phase0/frontend-stack.txt, evidence/hypeterminal/file-tree.txt |
| React 19 + Vite 7 + TS | USED | 1.15, 4.1 | React 19.2.8, Vite 7.3.6, TypeScript 5.9.3. Seven-panel terminal builds clean and renders real agent data at 46.63% ink coverage | evidence/phase4/density-measured.md |
| Tailwind v4 | USED | 1.15, 4.1 | CSS-first config, no tailwind.config.js. Two-layer token system with a type scale shifted one step down (12px/16px data rows), copied from HypeTerminal's globals.css:25-107 | ui-v2/src/index.css, evidence/ui-study.md |
| lucide-react | INSTALLED, NOT YET USED | 1.15 | No icon is on screen yet. Deliberate: R-STYLE says icons not emojis, and an icon added before it labels something is decoration | evidence/phase0/frontend-stack.txt |
| framer-motion | INSTALLED, NOT YET USED | 1.15 | A terminal that animates its numbers is harder to read. Reserved for the demo-run transitions in Phase 9 if they earn it | evidence/phase0/frontend-stack.txt |

## Learning and adaptive

| tool | status | task | what it produced | evidence |
|---|---|---|---|---|
| river 0.25.0 | USED | 1.14, 8.4 | Progressive-validation logistic model over 79 real agent decisions: 0.8608 accuracy against a 0.8354 majority-class baseline, i.e. 2 extra correct predictions. First run scored 0.8736/0.7586 because it included 8 naive-baseline CONTROL rows, found by 1.16's DuckDB aggregation. Decision recorded: BENCHMARK ONLY, not a sidecar | evidence/phase0/river.txt, docs/decisions/ADR-011-river-role.md |
| Burn / Candle | EVALUATED-REJECTED | 1.14 eval | No neural model is trained anywhere in this build. The learning layer settles single-digit-to-low-double-digit outcomes with a clamped update; a tensor framework at that sample size fits noise. Same reason 1.10 rejected drift detectors | docs/decisions/ADR-011-river-role.md |

## Coordination and infrastructure

| tool | status | task | what it produced | evidence |
|---|---|---|---|---|
| tiny_http 0.12 | USED | 6.2 | Replaced the hand-rolled accept loop AND its request parser, which is where the burst stall lived. The 40-request burst went from 802 seconds of client timeouts to 0.28 seconds, /thesis from never answering to 0.57ms, and the rate limiter was observed tripping for the first time in this project | evidence/phase6/burst-fixed.md, crates/coordination-api/src/main.rs |
| Axum / Actix / Tonic | EVALUATED-REJECTED | 6.2 eval | All three bring an async runtime. tiny_http gave concurrency with threads instead, which is enough for an endpoint whose request path performs ZERO I/O: every chain read moved to a refresher thread, so a handler is pure computation over a cached snapshot. The original reason recorded here, that the server was 120 hand-rolled single-threaded lines, no longer holds and is corrected rather than left standing | evidence/phase6/burst-fixed.md |
| OpenTelemetry + tracing | DEFERRED | 6.8 | A Cargo dependency added with the code that emits spans. Adding it now puts a dependency in Cargo.toml that nothing calls | evidence/phase0/support-tools.txt |
| DuckDB 1.5.5 | USED | 1.16, 8.6 | Aggregated all 87 journal rows straight from JSONL with no ETL step, and that query is what exposed the 8 naive-baseline control rows contaminating the river benchmark | evidence/phase0/support-tools.txt |

## Quality and productivity

| tool | status | task | what it produced | evidence |
|---|---|---|---|---|
| gitleaks 8.30.1 | USED | 0.5 | Full-history scan, 1 finding triaged as an intentional public demo key | evidence/internal/HYGIENE-LOG.md |
| codebase-memory-mcp 0.9.0 | USED | 1.9, 2.2 | Repo indexed to 5051 nodes / 12913 edges. Returns RiskApproved at crates/risk-engine/src/lib.rs:251 with its 4 methods, score_take at crates/decision-engine/src/lib.rs:289, 99 RiskGuard nodes; an invented symbol returns total:0, so the hits are signal | evidence/phase0/codebase-memory-mcp.txt |
| gemini-grounding | SUBSTITUTED | 1.11 | FAILS ON QUOTA, not capability: key authenticates (full model list returned, authenticated 404s, never 401), DoH-pinned native v1beta transport reaches the host, refusal is HTTP 429 on every model. This CORRECTS the v1 record, which called it unavailable on a 401 from an OpenAI-compatible route exactly as E3 predicts. No Gemini answer is quoted as grounded anywhere in this repo | evidence/phase0/gemini-grounding.txt |
| paperscraper | USED | 1.10 | 15 real arxiv records across 3 queries, 4 design decisions cited in docs/research-basis.md (2 IMPLEMENTED, 2 CONSIDERED-REJECTED). First version of the script printed a PASS while the query returned 0 records; the verdict is now gated on the real count | evidence/phase0/paperscraper.txt, docs/research-basis.md |
| opentelemetry 0.32 + opentelemetry_sdk 0.32.1 + opentelemetry-stdout 0.32 | USED | 14.3 | The real OpenTelemetry Rust SDK traces one decision: 5 spans, one 128-bit SDK-assigned trace id, four children parented to the root by OpenTelemetry's own `Context`. ADR-019 originally REJECTED this library on the untested claim that crates.io was unreachable from this machine; index.crates.io and static.crates.io both return 200 and `cargo add` resolved first try. The 403 is on the web frontend, which cargo never contacts. The exporter is `stdout`, not OTLP-over-gRPC, because that one needs a collector process and a trace nobody can read without infrastructure is not evidence | evidence/phase14/trace.md, evidence/phase14/otel-stdout.txt |
| proptest | USED | v1 P2/P4 | Property tests on every risk limit and on ranking determinism | evidence/mutation-risk-engine.md |
| just | USED | 1.16 | justfile at repo root with 8 recipes, each wrapping a command that already appears in an evidence file. Parses and lists | evidence/phase0/support-tools.txt, justfile |
| insta | DEFERRED | 8.6 | Not installed yet, deliberately: the journal renderer changes in Phases 4 and 8, and a snapshot taken now would be blessed-and-updated at every step, which trains diff-blessing | evidence/phase0/support-tools.txt |
| direnv | NOT-INSTALLED | 1.16 | Environment indirection this build does not need; environment is documented in CLAUDE.md E1-E9. | evidence/phase0/tool-substitutions.md |
| mise | NOT-INSTALLED | 1.16 | Same reason as direnv. | evidence/phase0/tool-substitutions.md |
