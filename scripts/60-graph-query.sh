#!/usr/bin/env bash
# Generic graph query, so R-SEARCH-4 (query the graph, do not grep) is cheap to obey.
# Usage: bash 60-graph-query.sh <query> [limit]
#
# The formatter lives in its own .py file rather than inline: escaping double quotes inside an
# f-string inside a shell single-quoted -c string is a syntax error waiting to happen, and it
# already happened once here.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
Q="${1:?query required}"
LIM="${2:-12}"
codebase-memory-mcp cli search_graph --project asml-x --query "$Q" --limit "$LIM" 2>&1 \
  | grep -vE 'level=(info|warn)' \
  | /home/zulab/.asml-venv/bin/python "$(dirname "$0")/graph_fmt.py"
