#!/usr/bin/env bash
# Find every script number TASKS.md plans that is already taken on disk by a DIFFERENT script.
#
# This collision has now bitten three times (Phase 7, Phase 8, Phase 9), each time costing a
# renumber mid-phase and a stale COMMAND line in the plan. Checking it once up front is cheaper than
# discovering it per phase.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

echo "== planned scripts whose number is already used by a different file =="
FOUND=0
for f in $(grep -oE "scripts/[0-9]{3}-[a-z0-9-]+\.sh" TASKS.md | sort -u); do
  n=$(basename "$f" | cut -c1-3)
  existing=$(ls scripts/ 2>/dev/null | grep "^$n-" | head -1)
  if [ -n "$existing" ] && [ "scripts/$existing" != "$f" ]; then
    echo "  COLLISION  plan wants $f  but $n- is taken by scripts/$existing"
    FOUND=$((FOUND + 1))
  fi
done
[ "$FOUND" -eq 0 ] && echo "  none"

echo
echo "== duplicate numbers within TASKS.md itself =="
grep -oE "scripts/[0-9]{3}-" TASKS.md | sort | uniq -d | sed 's/^/  /' || true

echo
echo "collisions: $FOUND"
