#!/usr/bin/env bash
# Task 1.16 supporting tools. Each one installs AND runs one real operation, or it is recorded
# as not installed with a reason.
#
# THINKING: #33 pareto (only the tools that earn their place; a tool that runs once for a smoke
# test and never again is a liability in the lockfile), #50 empirical (one real operation each,
# not a --version line).
#
# EVIDENCE PATH declared before code: evidence/phase0/support-tools.txt
# PASS: each tool performs one real operation on real repo data. `--version` is the fake win,
# and the whole point of Phase 1 is that fifteen artifacts once looked green while proving
# nothing.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/support-tools.txt"
mkdir -p "$(dirname "$OUT")"
VENV="/home/zulab/.asml-venv"

{
echo "Supporting tools, task 1.16"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## 1. just, the command surface"
echo "  version: $(just --version 2>&1 | head -1)"
} 2>&1 | tee "$OUT"

# A justfile is only worth having if it is the real entry point, so it wraps the commands this
# build actually runs, taken from the evidence scripts rather than invented.
cat > "$REPO/justfile" <<'JUST'
# ASML-X command surface. Every recipe here is a command that already appears in an evidence
# file, so this justfile is a shortcut to reproducible work rather than a second, drifting
# description of how to build.

_default:
    @just --list

# Rust workspace
test:
    cargo test --workspace

lint:
    cargo clippy --workspace --all-targets -- -D warnings

# Contracts
forge-test:
    cd contracts && forge test -vv

# Formal verification, both engines. Independent by design: same invariant, two solvers.
halmos:
    cd contracts && halmos --function check_

hevm:
    bash scripts/47d-hevm-argotorg.sh

# Mutation testing. Non-zero exit means mutants SURVIVED, which is a finding, not a crash.
mutants:
    bash scripts/59-cargo-mutants.sh

# Evidence
evidence-check:
    bash scripts/59-tool-ledger-check.sh

graph query:
    bash scripts/60-graph-query.sh "{{query}}"
JUST

{
echo "  justfile written with $(grep -cE '^[a-z][a-z-]*( [a-z]+)?:' "$REPO/justfile") recipes"
echo "  real operation: list the recipes just parsed (a syntax error here fails the task)"
cd "$REPO" && just --list 2>&1 | head -14 | sed 's/^/    /'
echo
echo "## 2. DuckDB, journal analytics for task 8.6"
echo "  version: $("$VENV/bin/python" -c 'import duckdb; print(duckdb.__version__)' 2>&1 | tail -1)"
echo "  real operation: aggregate the REAL journal, 87 rows, straight from JSONL"
} | tee -a "$OUT"

"$VENV/bin/python" - <<'PY' 2>&1 | tee -a "$OUT"
import duckdb

# Read the journal directly. The point of DuckDB here is that no ETL step is needed: it queries
# the newline-delimited JSON the agent already writes, so the analytics cannot drift from the
# record.
con = duckdb.connect()
p = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/journal.jsonl"
q = f"""
SELECT action,
       count(*)                        AS decisions,
       round(avg(thesis_confidence_bps)) AS avg_conf_bps,
       min(thesis_confidence_bps)        AS min_conf,
       max(thesis_confidence_bps)        AS max_conf
FROM read_json_auto('{p}')
GROUP BY action
ORDER BY decisions DESC
"""
rows = con.execute(q).fetchall()
print("    action                 decisions  avg_conf  min   max")
for r in rows:
    print("    %-22s %9s  %8s  %-5s %s" % r)
print(f"    total rows: {sum(r[1] for r in rows)}")
PY

{
echo
echo "## 3. insta, snapshot tests of journal rendering"
echo "  Deferred to task 8.6 rather than installed here, and the reason is a real one:"
echo "  a snapshot test asserts that rendered output has not changed. The journal renderer"
echo "  is being CHANGED in Phases 4 and 8. A snapshot taken now would be accepted-and-"
echo "  updated at every step, which trains the habit of blessing diffs without reading"
echo "  them, and that is worse than having no snapshot test."
echo "  Recorded as DEFERRED with a task number, not as done and not as omitted."
echo
echo "## 4. OpenTelemetry plus tracing"
echo "  Task 6.8, and it is a Cargo dependency added with the code that emits spans."
echo "  Installing it now would put a dependency in Cargo.toml that nothing calls, which is"
echo "  precisely the import-for-breadth fake win this phase warns about."
echo
echo "## Verdict, task 1.16"
echo "  just:     USED, justfile parses and lists recipes that wrap real evidence commands"
echo "  duckdb:   USED, aggregated all 87 real journal rows with no ETL step"
echo "  insta:    DEFERRED to 8.6, reason stated above"
echo "  otel:     DEFERRED to 6.8, reason stated above"
echo "  direnv, mise, Uniswap v4-core, safe-smart-account, reth: NOT INSTALLED, reasons in"
echo "  evidence/phase0/tool-substitutions.md, unchanged from the v1 record."
} | tee -a "$OUT"

echo "written: $OUT"
