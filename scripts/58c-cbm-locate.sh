#!/usr/bin/env bash
# Where did npm actually put it? Script 58 resolved the binary; 58b did not, with what looked
# like the same PATH. Find the real location instead of adjusting PATH by guesswork.
set -uo pipefail
. ./lib.sh
export PATH="/home/zulab/.npm-global/bin:$PATH"
echo "npm prefix: $(npm config get prefix 2>&1 | tail -1)"
echo "which: $(command -v codebase-memory-mcp || echo NOT-ON-PATH)"
echo "--- npm-global/bin ---"
ls -1 /home/zulab/.npm-global/bin 2>/dev/null | head
echo "--- filesystem search ---"
find /home/zulab /usr/local/bin -maxdepth 6 -name 'codebase-memory-mcp*' 2>/dev/null | head
