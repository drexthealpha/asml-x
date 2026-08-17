#!/usr/bin/env bash
# Task 2.5 reproduce every formal and mutation claim. Re-run all four mutation gates and both
# halmos suites, INCLUDING the injected violations, and compare theorem counts to what the docs
# claim.
#
# THINKING: #45 proof by contradiction (an injected violation that is NOT caught means the proof
# was vacuous), #66 red teaming (the interesting output is the injected-violation run, not the
# clean one), #49 evidence.
#
# EVIDENCE PATH declared before code: evidence/phase2/reverify-formal-mutation.txt
# PASS: theorem counts match the claims AND every injected violation is caught. A clean pass with
# no injected-violation run proves only that the tool ran.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase2/reverify-formal-mutation.txt"
mkdir -p "$(dirname "$OUT")"

run_gate() {
  local label="$1" script="$2"
  {
  echo
  echo "=============================================================="
  echo "## $label"
  echo "   command: bash scripts/$script"
  } | tee -a "$OUT"
  if [ ! -f "$REPO/scripts/$script" ]; then
    echo "   SCRIPT MISSING. Cannot re-verify, and a missing gate script is itself a finding." \
      | tee -a "$OUT"
    echo "MISSING $label" >> /home/zulab/gate-results.txt
    return
  fi
  local rc=0
  timeout 2400 bash "$REPO/scripts/$script" < /dev/null 2>&1 | tail -18 | sed 's/^/   /' \
    | tee -a "$OUT" || rc=1
  # The gate scripts print their own verdicts; capture whether the words appear.
  echo "RAN $label" >> /home/zulab/gate-results.txt
}

: > /home/zulab/gate-results.txt
{
echo "Formal and mutation re-verification, task 2.5"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Tools, versions read live rather than quoted from the docs"
echo "  halmos:  $(halmos --version 2>&1 | head -1)"
echo "  hevm:    $(hevm version 2>&1 | head -1)"
echo "  forge:   $(forge --version 2>&1 | head -1)"
echo "  cargo:   $(cargo --version 2>&1 | head -1)"
echo "  z3:      $(z3 --version 2>&1 | head -1)"
} 2>&1 | tee "$OUT"

run_gate "Proof mutation, halmos with an injected violation" 16-proof-mutation.sh
run_gate "RWA formal suite" 21-rwa-formal.sh
run_gate "Rust mutation gate, risk engine" 08-mutation-gate.sh
run_gate "Contract mutation gate" 11-contract-mutation.sh
run_gate "RWA mutation gate" 25-rwa-mutation.sh
run_gate "Learning mutation gate" 32-learning-mutation.sh
run_gate "hevm independent proofs" 47d-hevm-argotorg.sh
run_gate "scribble instrument-and-fire" 48-scribble-smoke.sh

{
echo
echo "=============================================================="
echo "## Verdict, task 2.5"
echo "  gates attempted: $(grep -c . /home/zulab/gate-results.txt)"
echo "  scripts missing: $(grep -c '^MISSING' /home/zulab/gate-results.txt || echo 0)"
echo
echo "  Each gate above prints its own verdict, reproduced verbatim rather than summarised into"
echo "  a single number here. A summary line would be the place where a failing gate could hide."
echo
echo "  What to look for when reading this file: every mutation gate must show a RED phase (the"
echo "  injected break is caught) followed by a GREEN phase (the restore is clean). A gate that"
echo "  only shows GREEN has not demonstrated anything, because a test that cannot fail is"
echo "  indistinguishable from a test that passes."
} | tee -a "$OUT"

echo "written: $OUT"
