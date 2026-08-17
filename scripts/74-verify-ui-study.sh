#!/usr/bin/env bash
# Task 3.7 / 3.8 enforcement: check that evidence/ui-study.md's citations are REAL.
#
# THINKING: #60 falsifiability (a study full of citations nobody checked is the same fake win as
# a study with none), #66 red teaming (the way this document fails is a plausible-looking
# path:line that does not contain what the sentence says), #50 empirical.
#
# What this checks, and what it deliberately does not:
#   CHECKS: every cited file exists in the studied clone, and every cited line number is within
#           that file's length. Also counts the citations so the document cannot overstate them.
#   DOES NOT CHECK: that the line says what the sentence claims. That needs a reader. But a
#           citation pointing past the end of a file is a fabrication detectable by machine, and
#           that is the failure worth automating.
#
# EVIDENCE PATH: evidence/hypeterminal/citation-audit.txt
# PASS: zero citations point at a missing file or a line beyond the file's length, and the count
# is at least 30.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/hypeterminal/citation-audit.txt"
mkdir -p "$(dirname "$OUT")"
SRC="/home/zulab/hypeterminal"
STUDY="$REPO/evidence/ui-study.md"

{
echo "ui-study.md citation audit, tasks 3.7 and 3.8"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Source"
echo "  study:  evidence/ui-study.md"
echo "  clone:  $SRC at $(cd "$SRC" && git rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)"
echo
} 2>&1 | tee "$OUT"

STUDY="$STUDY" SRC="$SRC" /home/zulab/.asml-venv/bin/python "$REPO/scripts/verify_citations.py" \
  2>&1 | tee -a "$OUT"
RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict"
if [ "${RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. Every cited file exists and every cited line is inside it, and the"
  echo "  citation count clears the gate's threshold of 30."
  echo "  Reproduce: bash scripts/74-verify-ui-study.sh"
else
  echo "  RESULT: FAIL. See the rows marked BAD above. A citation that points past the end of a"
  echo "  file is a fabricated citation, and the FRONTEND GATE stays shut until it is fixed."
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit "${RC:-1}"
