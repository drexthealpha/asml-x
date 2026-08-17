#!/usr/bin/env bash
# Task 3.1 clone and map HypeTerminal. This is the study gate: no frontend code exists until
# evidence/ui-study.md cites this repository by file and line.
#
# THINKING: #15 reductionist (decompose a monorepo into its packages before reading any of it),
# #11 systems thinking (the interesting part is how the four packages talk to each other),
# #37 visual/spatial.
#
# The clone goes OUTSIDE the product repo, at /home/zulab/hypeterminal. It is a reference to
# read, not a dependency to ship, and vendoring someone else's monorepo into this tree would
# both bloat the repo and blur whose code is whose.
#
# EVIDENCE PATH declared before code: evidence/hypeterminal/file-tree.txt
# PASS: tree captured, the four packages identified, total LOC recorded. The fake win named in
# TASKS.md is skimming the README, so this script deliberately produces LINE COUNTS PER FILE:
# the study that follows has to cite line numbers, and it cannot do that from a README.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/hypeterminal/file-tree.txt"
mkdir -p "$(dirname "$OUT")"
SRC="/home/zulab/hypeterminal"

{
echo "HypeTerminal structure map, task 3.1"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Clone"
echo "  source: https://github.com/vipineth/hypeterminal"
echo "  local:  $SRC  (OUTSIDE the product repo: a reference, not a dependency)"
} 2>&1 | tee "$OUT"

if [ -d "$SRC/.git" ]; then
  echo "  already cloned, fetching" | tee -a "$OUT"
  (cd "$SRC" && timeout 300 git fetch --depth 1 origin 2>&1 | tail -3 | sed 's/^/    /') | tee -a "$OUT"
else
  timeout 900 git clone --depth 1 https://github.com/vipineth/hypeterminal "$SRC" 2>&1 \
    | tail -6 | sed 's/^/    /' | tee -a "$OUT"
fi

if [ ! -d "$SRC" ]; then
  {
  echo
  echo "## Verdict, task 3.1"
  echo "  RESULT: FAIL. Clone did not produce a directory, so the study gate cannot open."
  echo "  Per the FRONTEND GATE this BLOCKS all frontend work rather than downgrading it."
  } | tee -a "$OUT"
  exit 1
fi

cd "$SRC"
{
echo
echo "## Commit actually studied, so the citations below are pinned to something"
git log -1 --format='  commit %H%n  date   %ad%n  subject %s' 2>&1
echo
echo "## Top level"
ls -1 2>&1 | sed 's/^/    /'
echo
echo "## Packages found under apps/ and packages/"
for d in apps/* packages/*; do
  [ -d "$d" ] || continue
  N=$(find "$d" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.css' \) 2>/dev/null | wc -l)
  L=$(find "$d" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.css' \) -exec cat {} + 2>/dev/null | wc -l)
  printf '    %-34s %4s files  %6s lines\n' "$d" "$N" "$L"
done
echo
echo "## The four packages TASKS.md 3.1 says to expect, checked rather than assumed"
for p in apps/terminal packages/hl-react packages/ui packages/hyperliquid-api; do
  if [ -d "$p" ]; then
    echo "    PRESENT  $p"
  else
    echo "    ABSENT   $p   <- the expected structure has changed, and the study must follow"
    echo "                    the repository rather than the expectation"
  fi
done
echo
echo "## Stack, read from the manifests rather than from the task description"
for f in package.json apps/terminal/package.json packages/ui/package.json; do
  [ -f "$f" ] || continue
  echo "  $f"
  grep -oE '"(react|react-dom|vite|tailwindcss|@tanstack/[a-z-]+|@base-ui[^"]*|class-variance-authority|lightweight-charts|typescript)": "[^"]+"' "$f" \
    2>/dev/null | sed 's/^/    /'
done
echo
echo "## Every source file with its line count. This is the index the study cites from."
find . -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.css' \) \
  -not -path './node_modules/*' -not -path './.git/*' 2>/dev/null \
  | sort | while read -r f; do
      printf '    %6s  %s\n' "$(wc -l < "$f")" "${f#./}"
    done
echo
TOTAL=$(find . -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.css' \) \
  -not -path './node_modules/*' -not -path './.git/*' -exec cat {} + 2>/dev/null | wc -l)
FILES=$(find . -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.css' \) \
  -not -path './node_modules/*' -not -path './.git/*' 2>/dev/null | wc -l)
echo "## Totals"
echo "  source files: $FILES"
echo "  total lines:  $TOTAL"
echo
echo "## Verdict, task 3.1"
echo "  RESULT: PASS if the four packages are PRESENT above and the totals are non-zero."
echo "  Reproduce: bash scripts/73-clone-hypeterminal.sh"
echo "  The per-file line counts exist so that 3.2 through 3.5 can cite file:line rather than"
echo "  describing an impression of the codebase, which is the failure mode this phase names."
} 2>&1 | tee -a "$OUT"

echo "written: $OUT"
