#!/usr/bin/env bash
# Task 0.2: every script referenced as a reproduce command in CHAIN-OF-EVIDENCE.md must
# still be TRACKED by git.
#
# This is the counter-task to the Phase 0 fake win. Pattern-matching script numbers into
# .gitignore is easy and it silently destroys the judge's ability to verify any claim whose
# command lives in an ignored file.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

OUT="$REPO/evidence/hygiene/evidence-scripts-tracked.txt"
mkdir -p "$(dirname "$OUT")"
INDEX="$REPO/evidence/CHAIN-OF-EVIDENCE.md"
FAIL=0

{
echo "Evidence script tracking gate, task 0.2"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

# Pull scripts referenced by TABLE ROWS only, not by prose.
#
# The first version grepped the whole file, so the scope note's prose mention of
# scripts/39-repo-hygiene-audit.sh registered as a dependency and produced a false failure.
# Only a row in the claim table is an actual dependency a judge would need to run.
grep '^| C-' "$INDEX" 2>/dev/null \
  | grep -oE 'scripts/[A-Za-z0-9_-]+\.(sh|py)' | sort -u > /tmp/idx_scripts.txt
COUNT=$(wc -l < /tmp/idx_scripts.txt)
echo "scripts referenced by the index: $COUNT"
echo

while read -r S; do
  [ -z "$S" ] && continue
  if [ ! -f "$REPO/$S" ]; then
    printf '  [FAIL] %-46s DOES NOT EXIST\n' "$S"
    FAIL=$((FAIL+1))
    continue
  fi
  if git check-ignore -q "$S" 2>/dev/null; then
    printf '  [FAIL] %-46s IGNORED, judge cannot run it\n' "$S"
    FAIL=$((FAIL+1))
  elif git ls-files --error-unmatch "$S" >/dev/null 2>&1; then
    printf '  [PASS] %-46s tracked\n' "$S"
  else
    # Untracked but NOT ignored is expected for a new file: R-GIT forbids this build from
    # committing, so new scripts sit untracked until the user commits them. That is a
    # handoff item, not a failure. Only IGNORED is a real defect.
    printf '  [PEND] %-46s untracked, awaiting the user commit (not ignored)\n' "$S"
  fi
done < /tmp/idx_scripts.txt

echo
echo "Also checking the reverse: ignored scripts that produce judge-facing evidence."
echo "(An ignored script is fine ONLY if nothing in the index depends on it.)"
git ls-files --others --ignored --exclude-standard 2>/dev/null | grep -E '^scripts/.*\.(sh|py)$' | while read -r IG; do
  if grep '^| C-' "$INDEX" 2>/dev/null | grep -q "$IG"; then
    printf '  [FAIL] %-46s ignored BUT referenced by the index\n' "$IG"
  else
    printf '  [ok]   %-46s ignored, not referenced\n' "$IG"
  fi
done

echo
echo "failures: $FAIL"
} | tee "$OUT"

[ "$FAIL" = "0" ] || exit 1
exit 0
