#!/usr/bin/env bash
# 1.9 probe. Read the two tools' real flag interfaces and the worker crash log. Three facts
# the tool told me about itself, all of which my first invocation got wrong:
#   1. raw JSON is deprecated, use flags
#   2. search_graph requires a `project` argument, from list_projects
#   3. the index worker crashed on some file, and it logged WHICH log file to read
# E4: no $PATH expansion through the wsl arg layer, so this is a script.
set -uo pipefail
# The npm package's postinstall drops a static binary in ~/.local/bin, NOT in the npm prefix
# bin. npm-global/bin holds only scribble. That is why this probe reported command-not-found
# while script 58 resolved it fine: 58 sources lib.sh, which has ~/.local/bin on PATH.
export PATH="/home/zulab/.local/bin:/home/zulab/.npm-global/bin:$PATH"
echo "=== index_repository --help ==="
codebase-memory-mcp cli index_repository --help 2>&1 | head -34
echo
echo "=== search_graph --help ==="
codebase-memory-mcp cli search_graph --help 2>&1 | head -26
echo
echo "=== list_projects ==="
codebase-memory-mcp cli list_projects 2>&1 | grep -v 'level=info' | head -10
echo
echo "=== newest worker crash log ==="
LOG=$(ls -t /home/zulab/.cache/codebase-memory-mcp/logs/.worker-*.log 2>/dev/null | head -1)
echo "log: ${LOG:-none}"
[ -n "$LOG" ] && tail -14 "$LOG"
