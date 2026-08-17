#!/usr/bin/env bash
# Task 1.2 done properly: install halmos 0.3.3 and compare it against the 0.1.13 that
# actually proved v1's 14 theorems.
#
# THINKING: #49 skeptical (the VERIFIED FACTS table said 0.3.3 and the box had 0.1.13, so
# the table was an assumption wearing a label), #13 dialectical (two prover versions
# disagreeing on the same theorem is the most valuable outcome available), #50 empirical.
#
# Python 3.10.12 is below halmos 0.3.3's requires_python >=3.11 (verified from the PyPI
# JSON API in 45b). uv ships its own interpreter, so it can satisfy that without touching
# the system Python, which is why the task list specifies uv.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/halmos.txt"
mkdir -p "$(dirname "$OUT")"

{
echo "halmos install and version comparison, task 1.2"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Starting state"
echo "  system python: $(python3 --version 2>&1)"
echo "  halmos on PATH: $(command -v halmos || echo none)"
echo "  halmos version: $(halmos --version 2>&1 | head -1 || echo none)"
echo
echo "  CORRECTION: the VERIFIED FACTS table claimed 0.3.3. The box has 0.1.13."
echo "  v1's 14 theorems were proven by 0.1.13, not by 0.3.3."
echo

echo "## Installing uv (brings its own Python, so the system 3.10 is untouched)"
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf --max-time 180 https://astral.sh/uv/install.sh -o "$HOME/uv-install.sh" 2>/dev/null
  if [ -s "$HOME/uv-install.sh" ]; then
    sh "$HOME/uv-install.sh" 2>&1 | tail -3
  else
    echo "  uv installer fetch FAILED"
  fi
fi
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
echo "  uv: $(uv --version 2>&1 | head -1 || echo NOT AVAILABLE)"
echo

if command -v uv >/dev/null 2>&1; then
  echo "## Installing halmos 0.3.3 on Python 3.12 via uv"
  uv tool install --python 3.12 'halmos==0.3.3' --force 2>&1 | tail -6
  echo
  echo "  halmos now: $(halmos --version 2>&1 | head -1)"
else
  echo "## uv unavailable. R-SEARCH-2 ladder for this step:"
  echo "   1 gemini-grounding: unavailable on this network (task 1.11)"
  echo "   2 WebSearch: confirmed 0.3.3 requires_python >=3.11"
  echo "   3 DoH-pinned fetch: PyPI JSON confirmed the same (45b)"
  echo "   4 browser render: not attempted, the metadata was already obtained"
  echo "   Substitute: keep halmos 0.1.13, which demonstrably proves the 14 theorems."
fi
} | tee "$OUT"

echo
echo "=== running the RWA suite under whatever halmos is now active ==="
if bash "$REPO/scripts/21-rwa-formal.sh" > "$HOME/halmos-rwa-run.txt" 2>&1; then
  RESULT=PASS
else
  RESULT=FAIL
fi
grep -E '^\[PASS\]|^\[FAIL\]|^\[ERROR\]|Symbolic test result|caught=' "$HOME/halmos-rwa-run.txt" \
  | tail -14 | tee -a "$OUT"

{
echo
echo "## Verdict"
echo "  suite exit: $RESULT"
echo "  version used: $(halmos --version 2>&1 | head -1)"
echo
echo "  PASS condition for 1.2 is BOTH: 7 theorems pass AND the injected violation is"
echo "  caught. A pass alone is not enough, because a prover that verifies zero tests"
echo "  also exits 0. The caught= line above is the half that matters."
} | tee -a "$OUT"

echo
echo "written: $OUT"
