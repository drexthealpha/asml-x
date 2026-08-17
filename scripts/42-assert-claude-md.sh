#!/usr/bin/env bash
# Task 0.4: CLAUDE.md must exist ON DISK at the repo root, be gitignored, and carry every
# rule id. It is the only file that survives context compaction, so it is what stops rule
# drift between sessions. Never delete it from disk, only from git tracking.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

OUT="$REPO/evidence/hygiene/claude-md-check.txt"
mkdir -p "$(dirname "$OUT")"
FAIL=0

{
echo "CLAUDE.md gate, task 0.4"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

if [ -f "$REPO/CLAUDE.md" ]; then
  echo "[PASS] exists on disk: CLAUDE.md ($(wc -l < "$REPO/CLAUDE.md") lines)"
else
  echo "[FAIL] CLAUDE.md MISSING FROM DISK. Recreate it immediately."
  FAIL=$((FAIL+1))
fi

if git check-ignore -q CLAUDE.md 2>/dev/null; then
  echo "[PASS] gitignored"
else
  echo "[FAIL] not gitignored"
  FAIL=$((FAIL+1))
fi

if git ls-files --error-unmatch CLAUDE.md >/dev/null 2>&1; then
  echo "[FAIL] still TRACKED by git"
  FAIL=$((FAIL+1))
else
  echo "[PASS] not tracked by git"
fi

echo
echo "Required rule ids present in CLAUDE.md:"
for R in R-DEPTH-0 R-SEARCH-1 R-SEARCH-2 R-SEARCH-3 R-SEARCH-4 R-EVIDENCE R-MUTATE \
         R-PROVE-REALITY R-NO-CONFESSION R-NO-WRAPPER R-STYLE R-GIT R-WSL; do
  if grep -q "$R" "$REPO/CLAUDE.md" 2>/dev/null; then
    printf '  [PASS] %s\n' "$R"
  else
    printf '  [FAIL] %s MISSING\n' "$R"
    FAIL=$((FAIL+1))
  fi
done

echo
echo "Required environment facts E1..E9:"
for E in E1 E2 E3 E4 E5 E6 E7 E8 E9; do
  if grep -qE "^${E}[ :]" "$REPO/CLAUDE.md" 2>/dev/null || grep -q "^${E} " "$REPO/CLAUDE.md" 2>/dev/null; then
    printf '  [PASS] %s\n' "$E"
  else
    printf '  [FAIL] %s MISSING\n' "$E"
    FAIL=$((FAIL+1))
  fi
done

echo
echo "Goal statement present:"
if grep -qi "GOAL" "$REPO/CLAUDE.md" 2>/dev/null; then
  echo "  [PASS] GOAL section found"
else
  echo "  [FAIL] no GOAL section"
  FAIL=$((FAIL+1))
fi

echo
echo "failures: $FAIL"
} | tee "$OUT"

[ "$FAIL" = "0" ] || exit 1
exit 0
