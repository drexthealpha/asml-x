#!/usr/bin/env bash
# Task 2.7 backfill: populate CHAIN-OF-EVIDENCE.md. The index has a header, a scope note and
# ZERO rows, so right now nothing in the product resolves to a proof. This is the largest
# outstanding gap in the submission and it is not a documentation chore: R-EVIDENCE says a claim
# with no evidence path is DELETED, and with an empty index that rule would delete the README.
#
# THINKING: #49 evidence (every row is a claim plus the command that reproves it), #60
# map-territory (rows are added only where the artifact EXISTS, which is enforced by
# 43-chain-add.sh refusing a DEMONSTRATED row with a missing file), #19 critical thinking.
#
# EVIDENCE PATH: evidence/CHAIN-OF-EVIDENCE.md itself.
# PASS: every row added has an artifact on disk and a command that regenerates it. The fake win
# is a long index whose commands nobody ran, which is why 2.6 (`bash scripts/44-chain-verify.sh`)
# re-runs them and 1.19 deletes the evidence file first.
#
# Rows are added through 43-chain-add.sh rather than appended directly, so its two refusals
# apply to every row: a DEMONSTRATED row whose artifact is missing is rejected, and a duplicate
# id is rejected.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

ADD="bash $REPO/scripts/43-chain-add.sh"
LOG="$REPO/evidence/phase2/chain-backfill.txt"
mkdir -p "$(dirname "$LOG")"

add() {
  # id, claim, evidence, command, label, task
  if $ADD "$1" "$2" "$3" "$4" "$5" "$6" >> "$LOG" 2>&1; then
    echo "  added   $1  $5"
  else
    echo "  REFUSED $1  $(tail -1 "$LOG")"
  fi
}

: > "$LOG"
echo "Chain-of-evidence backfill, task 2.7" | tee -a "$LOG"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')" | tee -a "$LOG"
echo

echo "## Chain and deployment claims (task 2.3)"
add C-202 "X Layer testnet chain id is 1952; chain 195 is deprecated and still answers" \
    "evidence/phase2/chain-id.txt" "bash scripts/67-verify-deployments.sh" DEMONSTRATED 2.3
add C-203 "Mean block time measured at 1.000s over 300 blocks on chain 1952" \
    "evidence/phase2/chain-id.txt" "bash scripts/67-verify-deployments.sh" DEMONSTRATED 2.3
add C-204 "All 7 addresses in docs/verified/deployments.md return non-empty bytecode on chain 1952" \
    "evidence/phase2/deployment-bytecode.txt" "bash scripts/67-verify-deployments.sh" DEMONSTRATED 2.3
add C-205 "Deployer 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46 holds a funded balance and has sent transactions" \
    "evidence/phase2/chain-id.txt" "bash scripts/67-verify-deployments.sh" DEMONSTRATED 2.3

echo
echo "## Transaction claims (task 2.4)"
add C-211 "Every tx hash cited in a judge-facing document resolves on chain with status 0x1" \
    "evidence/phase2/tx-receipts.json, evidence/phase2/tx-claims.txt" \
    "bash scripts/68-verify-tx-claims.sh" DEMONSTRATED 2.4

echo
echo "## Formal verification (tasks 1.2, 1.4, 1.5)"
add C-220 "halmos 0.3.3 proves 7 theorems over RiskGuard and catches an injected violation" \
    "evidence/phase0/halmos.txt" "bash scripts/45c-halmos-upgrade.sh" DEMONSTRATED 1.2
add C-221 "hevm 0.57.0 independently proves 5 theorems over RiskGuard, a second engine on the same invariant" \
    "evidence/phase0/hevm.txt, contracts/test/HevmCapProofs.t.sol" \
    "bash scripts/47d-hevm-argotorg.sh" DEMONSTRATED 1.4
add C-222 "A scribble annotation on the cap invariant becomes a runtime check that FIRES: the plain contract accepts 150, the instrumented one reverts" \
    "evidence/phase0/scribble.txt, contracts/test/ScribbleFire.t.sol" \
    "bash scripts/48-scribble-smoke.sh" DEMONSTRATED 1.5
add C-223 "kontrol is substituted, not silently skipped: four R-SEARCH-2 rungs named and the capability covered by halmos plus hevm" \
    "evidence/phase0/kontrol.txt, evidence/phase0/tool-substitutions.md" \
    "bash scripts/46-kontrol-smoke.sh" DEMONSTRATED 1.3
add C-224 "act is substituted with the capability loss stated: Nix-only build, no release binary, and its strongest EVM backend is hevm which is already driven directly" \
    "evidence/phase0/act.txt, evidence/phase0/tool-substitutions.md" \
    "bash scripts/56-act-install.sh" DEMONSTRATED 1.6

echo
echo "## Mutation testing (task 1.7)"
add C-230 "cargo-mutants found 37 SURVIVING mutants in risk-engine: no limit boundary was pinned, the post-trade projection was never exercised against a non-empty book, the shipped defaults were unasserted, and is_halted had no test" \
    "evidence/phase0/cargo-mutants-risk-engine.txt" "bash scripts/59-cargo-mutants.sh" DEMONSTRATED 1.7
add C-231 "11 tests were written to kill those survivors and the re-mutation run records the result" \
    "evidence/phase0/cargo-mutants-after.txt" "bash scripts/66-remutate.sh" DEMONSTRATED 1.7

echo
echo "## Determinism and purity (ADR-005)"
add C-240 "risk-engine reads no clock: time is an argument, confirmed both by a graph query and by a direct check for SystemTime and Instant::now inside the crate" \
    "evidence/phase2/graph-query-log.txt" "bash scripts/64-graph-query-log.sh" DEMONSTRATED 2.2
add C-241 "RiskApproved<T> cannot be constructed outside risk-engine; forging one is a COMPILE error, with a test that asserts the bypass does not compile" \
    "evidence/phase2/graph-query-log.txt, crates/executor/src/lib.rs" \
    "bash scripts/64-graph-query-log.sh" DEMONSTRATED 2.2

echo
echo "## Research basis and learning (tasks 1.10, 1.14)"
add C-250 "15 real arxiv records were retrieved and 4 design decisions cite them, 2 IMPLEMENTED and 2 CONSIDERED-REJECTED" \
    "evidence/phase0/paperscraper.txt, docs/research-basis.md" \
    "bash scripts/51-paperscraper-smoke.sh" DEMONSTRATED 1.10
add C-251 "river scores 0.8608 against a 0.8354 majority baseline on 79 real agent decisions, which is 2 extra correct predictions and the reason it is a benchmark rather than a sidecar" \
    "evidence/phase0/river.txt, docs/decisions/ADR-011-river-role.md" \
    "bash scripts/55-river-smoke.sh" DEMONSTRATED 1.14
add C-252 "The journal contains 87 rows, of which 8 are naive-baseline control rows, established by a DuckDB aggregation over the raw JSONL" \
    "evidence/phase0/support-tools.txt" "bash scripts/62-support-tools.sh" DEMONSTRATED 1.16

echo
echo "## Toolchain and frontend (tasks 1.1, 1.9, 1.11, 1.15)"
add C-260 "The code graph indexes this repo to 5051 nodes and 12913 edges and answers structural queries with file:line, while an invented symbol returns zero results" \
    "evidence/phase0/codebase-memory-mcp.txt" "bash scripts/58-codebase-memory-mcp.sh" DEMONSTRATED 1.9
add C-261 "gemini-grounding fails on QUOTA, not on network or key: the API returns a full model list and authenticated 404s, and the refusal is HTTP 429 across three spaced attempts" \
    "evidence/phase0/gemini-grounding.txt" "bash scripts/57c-gemini-429.sh" DEMONSTRATED 1.11
add C-262 "The ui-v2 production build succeeds with all 16 dependency versions installed at exactly their pinned version, checked by a script that exits non-zero on any mismatch" \
    "evidence/phase0/frontend-stack.txt, ui-v2/pnpm-lock.yaml" \
    "bash scripts/61-frontend-scaffold.sh" DEMONSTRATED 1.15
add C-263 "The toolchain floor is verified rather than assumed, and the gate that checks it was itself fixed after printing a false green" \
    "evidence/phase0/toolchain.txt" "bash scripts/45-toolchain-floor.sh" DEMONSTRATED 1.1

echo
echo "## Claim inventory (task 2.1)"
add C-201 "244 factual assertions were extracted from 29 judge-facing documents, each with a file:line origin" \
    "evidence/phase2/claim-inventory.txt, evidence/phase2/claim-inventory.csv" \
    "bash scripts/63-claim-inventory.sh" DEMONSTRATED 2.1

echo
echo "## Architecture decision (task 1.17)"
add C-270 "No LLM agent framework sits on the decision path, and the falsification test is mechanical: no HTTP client or model provider dependency exists in decision-engine, risk-engine or executor" \
    "evidence/phase0/agent-framework-choice.md, docs/decisions/ADR-012-agent-framework.md" \
    "grep -rn 'reqwest|openai|anthropic|gemini' crates/decision-engine crates/risk-engine crates/executor" \
    DEMONSTRATED 1.17

echo
ROWS=$(grep -c '^| C-' "$REPO/evidence/CHAIN-OF-EVIDENCE.md" || echo 0)
{
echo "## Verdict, task 2.7 backfill"
echo "  rows in the index now: $ROWS"
echo "  Every row was added through scripts/43-chain-add.sh, which REFUSES a DEMONSTRATED row"
echo "  whose evidence file does not exist. So a row present here means the artifact is on disk."
echo "  What that does NOT yet prove is that each command REGENERATES its artifact from a clean"
echo "  state. That is task 2.6 (scripts/44-chain-verify.sh) and task 1.19, which delete the"
echo "  evidence file first and re-run the command."
} | tee -a "$LOG"

echo "log: $LOG"
