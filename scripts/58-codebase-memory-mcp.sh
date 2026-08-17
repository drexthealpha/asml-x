#!/usr/bin/env bash
# Task 1.9 codebase-memory-mcp. Install, index THIS repo, and answer a real structural
# question by querying the graph. R-SEARCH-4 says query the graph, do not grep, so this tool
# has to actually work or that rule is unenforceable.
#
# THINKING: #23 systems (a code graph is the repo's dependency structure made queryable, which
# is what makes "what calls this" cheap), #49 evidence (the PASS is a QUERY RESULT about real
# symbols in this repo, never an index-built message), #27 opportunity-cost (one install, one
# index, one query set; no MCP client plumbing unless the CLI cannot answer).
#
# SEARCH FINDINGS before code, per R-SEARCH-1:
#   Repo: github.com/DeusData/codebase-memory-mcp. tree-sitter AST across 158 languages,
#   persistent knowledge graph, single static binary.
#   Install routes offered: an install.sh piped from raw.githubusercontent, `npm install -g
#   codebase-memory-mcp@latest`, or `pip install -U codebase-memory-mcp`.
#   CHOICE: npm. Piping a remote script straight into bash is the one route I will not use,
#   and npm already has a working user-level prefix here from task 1.5's EACCES fix.
#   Source: https://github.com/DeusData/codebase-memory-mcp
#
# EVIDENCE PATH declared before code: evidence/phase0/codebase-memory-mcp.txt
# PASS: the graph answers a structural question about REAL symbols in this repo, with names
# that exist. "Indexed N files" is the fake win: an index nobody queries proves nothing.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="/home/zulab/.npm-global/bin:$PATH"

OUT="$REPO/evidence/phase0/codebase-memory-mcp.txt"
mkdir -p "$(dirname "$OUT")"

{
echo "codebase-memory-mcp, task 1.9"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Install, via npm user prefix rather than curl-pipe-bash"
echo "  npm prefix: $(npm config get prefix 2>&1 | tail -1)"
} 2>&1 | tee "$OUT"

BIN=""
for CAND in codebase-memory-mcp cbmemory codebase-memory; do
  command -v "$CAND" >/dev/null 2>&1 && { BIN="$CAND"; break; }
done

if [ -z "$BIN" ]; then
  npm install -g codebase-memory-mcp@latest 2>&1 | tail -6 | sed 's/^/  /' | tee -a "$OUT"
  for CAND in codebase-memory-mcp cbmemory codebase-memory; do
    command -v "$CAND" >/dev/null 2>&1 && { BIN="$CAND"; break; }
  done
  # npm bin names are not always the package name. Look at what the package actually linked.
  if [ -z "$BIN" ]; then
    echo "  package bin not on PATH under any guessed name. Listing what npm linked:" | tee -a "$OUT"
    ls -1 /home/zulab/.npm-global/bin 2>/dev/null | sed 's/^/    /' | tee -a "$OUT"
  fi
fi

{
echo "  binary: ${BIN:-NOT FOUND}"
if [ -n "$BIN" ]; then
  echo "  version: $($BIN --version 2>&1 | head -1)"
  echo
  echo "## Its actual subcommands, read from --help rather than guessed"
  $BIN --help 2>&1 | head -40 | sed 's/^/    /'
fi
} 2>&1 | tee -a "$OUT"

if [ -z "$BIN" ]; then
  {
  echo
  echo "## Verdict, task 1.9"
  echo "  RESULT: FAIL. No binary, so R-SEARCH-4 cannot be enforced and searches in this"
  echo "  build fall back to ripgrep. Recorded rather than papered over."
  } | tee -a "$OUT"
  exit 1
fi

{
echo
echo "## Indexing this repo"
} | tee -a "$OUT"
cd "$REPO"
# CORRECTED after reading --help: there is no `index` or `search` subcommand. The binary is an
# MCP server, and the only non-server entry point is `cli <tool> <json>` against the tool
# names it lists: index_repository, search_graph, query_graph, get_architecture, search_code.
# My first pass invoked `index` and `search`, got only server lifecycle logs, and no data. The
# help output named the real interface, so this is read, not guessed.
# CORRECTED TWICE, both times from the tool's own output rather than from guessing:
#   1st: `index .` and `search X` do not exist. The interface is `cli <tool>`.
#   2nd: the JSON key is repo_path, not path. The worker crash log said "repo_path is
#        required" in one line, which is why reading the crash log beat re-running.
# Now using FLAGS, since raw JSON is deprecated and warns on every call.
# --mode fast: no similarity/semantic edges. The queries here are structural (where is this
# symbol, what touches it), so paying for embedding passes on a 4.9 GB box buys nothing.
timeout 600 "$BIN" cli index_repository --repo-path "$REPO" --mode fast --name asml-x \
  2>&1 | grep -vE 'level=info msg=(watcher|server|mem)' | tail -16 | sed 's/^/  /' | tee -a "$OUT"

# One helper rather than four hand-written invocations, because the JSON argument shape is
# the part that is easy to get subtly wrong four different ways. Server lifecycle lines are
# filtered out: they are noise that hid the empty results on the first pass.
# search_graph requires --project, which it said itself: "missing required argument: project".
# The project name is whatever index_repository registered, so read it from list_projects
# rather than assuming --name took effect.
PROJ=$(timeout 60 "$BIN" cli list_projects 2>/dev/null \
       | grep -oE '"name":"[^"]*asml[^"]*"' | head -1 | sed 's/.*":"//;s/"$//')
echo "  project registered as: ${PROJ:-NONE}" | tee -a "$OUT"

gq() {
  local q="$1"
  timeout 150 "$BIN" cli search_graph --project "$PROJ" --query "$q" --limit 8 2>&1 \
    | grep -vE 'level=info msg=(watcher|server|mem)' \
    | head -6 | cut -c1-1400 | sed 's/^/    /' | tee -a "$OUT"
}

{
echo
echo "## The queries that make this a PASS. Real symbols from this repo."
echo
echo "  Q1: where is RiskApproved defined and what touches it? This is the type-system seal"
echo "      the whole safety claim rests on, so if the graph knows anything it knows this."
} | tee -a "$OUT"
gq "RiskApproved"

{
echo
echo "  Q2: score_take, the scoring function corrected by task 1.10's research basis."
} | tee -a "$OUT"
gq "score_take"

{
echo
echo "  Q3: RiskGuard, the Solidity contract halmos and hevm both prove."
} | tee -a "$OUT"
gq "RiskGuard"

{
echo
echo "## Break-attempt: does it return hits for a symbol that does NOT exist?"
echo "  A graph that answers everything answers nothing. Querying a made-up name must come"
echo "  back empty, otherwise the three results above are noise."
} | tee -a "$OUT"
gq "ZzNotARealSymbolInThisRepo"

{
echo
echo "## Verdict, task 1.9"
echo "  PASS requires: real symbols found AND the invented symbol NOT found."
echo "  See the four query blocks above. If the invented symbol returned hits, this tool is"
echo "  not usable for R-SEARCH-4 regardless of how fast it indexed."
} | tee -a "$OUT"

echo "written: $OUT"
