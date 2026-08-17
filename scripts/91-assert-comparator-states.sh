#!/usr/bin/env bash
# Task 5.5 comparator completeness gate.
#
# THINKING: #19 critical thinking, #49 skeptical (the artifact this gate exists to prevent is a
# comparator that only ever shows refusals, which reads as a global brake and proves nothing).
#
# PASS per TASKS.md: "three files, correct verdicts". Expanded slightly because "three files" is
# checkable and weak on its own: this also asserts that HEALTHY has BOTH markets approving, that each
# refusing state names an RWA-SPECIFIC cause, and that the crypto market approved in every state. That
# last one is the real control: if crypto also refused, the difference would not be about the
# instrument.
#
# EVIDENCE PATH declared before code: evidence/phase5/comparator-gate.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase5/comparator-gate.txt"
mkdir -p "$(dirname "$OUT")"

{
echo "Comparator completeness gate, task 5.5"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
} 2>&1 | tee "$OUT"

/home/zulab/.asml-venv/bin/python "$REPO/scripts/assert_comparator.py" 2>&1 | tee -a "$OUT"
RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict, task 5.5"
if [ "${RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. Three states present with the verdicts the task requires."
  echo "  Reproduce: bash scripts/90-comparator-states.sh && bash scripts/91-assert-comparator-states.sh"
else
  echo "  RESULT: FAIL, see the rows above. The comparator is not shipped until this passes,"
  echo "  because a comparator missing its healthy state argues the opposite of what it claims."
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit "${RC:-1}"
