#!/usr/bin/env bash
# Task 5.2 assert no frontend-invented numbers.
#
# THINKING: #60 map-territory (a numeric literal in a render path is the UI asserting something the
# agent never said), #66 red teaming (the way this check fails is by only looking for obvious fake
# data, so it has to look at EVERY literal and force each one to be justified), #19 critical
# thinking.
#
# WHAT COUNTS AS A VIOLATION: a numeric literal that reaches the screen as DATA. Not every number in
# the source is one: grid spans, z-indices, slice bounds, poll intervals and colour alphas are
# layout and configuration. So the rule is not "no numbers", it is:
#   every numeric literal in ui-v2/src must be either
#     (a) in an allowed category (layout, config, domain bound, index arithmetic), or
#     (b) on a line carrying an explicit justification comment marker.
# and anything else fails the script.
#
# EVIDENCE PATH declared before code: evidence/phase5/no-magic-numbers.txt
# PASS: zero unexplained numeric literals in data render paths.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase5/no-magic-numbers.txt"
mkdir -p "$(dirname "$OUT")"

{
echo "No-invented-numbers audit, task 5.2"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
} 2>&1 | tee "$OUT"

/home/zulab/.asml-venv/bin/python "$REPO/scripts/no_magic_numbers.py" 2>&1 | tee -a "$OUT"
RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict, task 5.2"
if [ "${RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. Every numeric literal in ui-v2/src is either layout, configuration, a"
  echo "  domain bound, or index arithmetic. None is a data value."
  echo "  Reproduce: bash scripts/87-assert-no-magic-numbers.sh"
else
  echo "  RESULT: FAIL. The literals listed above reach the screen without a source. Each one is"
  echo "  either wired to the data layer or deleted; a comment is not a fix."
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit "${RC:-1}"
