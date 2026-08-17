#!/usr/bin/env bash
# Task 1.7 cargo-mutants on risk-engine. R-MUTATE says a test that cannot fail is deleted, and
# cargo-mutants is the automated form of that: it edits the source, re-runs the suite, and any
# mutant that SURVIVES is a hole in the tests.
#
# THINKING: #22 inversion (do not ask whether tests pass, ask whether they can fail),
# #60 falsifiability (a surviving mutant is a falsified claim about coverage), #29
# margin-of-safety (bound the run: this box has 4.9 GB and one earlier unbounded run was lost
# when the distro restarted).
#
# WHAT WENT WRONG LAST TIME, recorded so it is not repeated: an earlier background run was
# checked with `pgrep -f mutants`, which matched the CHECKING command's own `bash -c` line and
# reported RUNNING every time. The distro had restarted and the output file did not exist. That
# check was a false positive I wrote. This script runs in the foreground of its own invocation
# and the evidence file's existence is the only status signal used.
#
# EVIDENCE PATH declared before code: evidence/phase0/cargo-mutants-risk-engine.txt
# PASS: a mutant score with the SURVIVORS NAMED, and a judgement on each survivor. A
# high score with unexamined survivors is the fake win, because the survivors are the finding.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/cargo-mutants-risk-engine.txt"
mkdir -p "$(dirname "$OUT")"

{
echo "cargo-mutants on risk-engine, task 1.7"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Tool and target"
echo "  cargo-mutants: $(cargo mutants --version 2>&1 | head -1)"
echo "  rustc:         $(rustc --version 2>&1 | head -1)"
echo "  target crate:  risk-engine, the crate holding RiskApproved<T> and every limit check"
echo
echo "## Why risk-engine specifically"
echo "  It is the only crate whose failure is unbounded. A wrong score costs a bad trade; a"
echo "  wrong limit check costs the cap. It is also the crate most amenable to mutation:"
echo "  pure integer arithmetic, no clock reads, no floats, so every mutant is deterministic"
echo "  and a survivor cannot be explained away as flakiness."
echo
echo "## Bounds, and why each"
echo "  --timeout 90        a mutant that hangs is a survivor by timeout, not by merit"
echo "  --in-place          this box has 4.9 GB RAM; cargo-mutants' default copies the tree"
echo "                      per job and that is what makes it thrash here"
echo "  (serial)            --in-place is INHERENTLY serial: cargo-mutants rejects"
echo "                      '--in-place with --jobs' outright, because one working tree"
echo "                      cannot hold two mutants at once. My first invocation passed"
echo "                      both and the tool refused, correctly."
echo
} 2>&1 | tee "$OUT"

cd "$REPO"
# --in-place mutates the working tree, so guarantee restoration whatever happens. R-GIT
# forbids commits, not a stash-free file-level backup, and this is the safest form available.
BACKUP="/home/zulab/risk-engine-src-backup"
rm -rf "$BACKUP"; mkdir -p "$BACKUP"
cp -r crates/risk-engine/src "$BACKUP/src"
restore() {
  rm -rf crates/risk-engine/src
  cp -r "$BACKUP/src" crates/risk-engine/src
  echo "  source restored from $BACKUP" | tee -a "$OUT"
}
trap restore EXIT

echo "## Running" | tee -a "$OUT"
timeout 3300 cargo mutants -p risk-engine --in-place --timeout 90 \
  --output /home/zulab/mutants-out 2>&1 | tail -40 | sed 's/^/  /' | tee -a "$OUT"
MUT_RC=${PIPESTATUS[0]}

{
echo
echo "## Outcome files"
ls -1 /home/zulab/mutants-out/mutants.out 2>/dev/null | sed 's/^/  /'
for f in caught.txt missed.txt timeout.txt unviable.txt; do
  P="/home/zulab/mutants-out/mutants.out/$f"
  [ -f "$P" ] && echo "  $f: $(wc -l < "$P") lines"
done

echo
echo "## THE FINDING: mutants that SURVIVED, which is where the holes are"
MISSED="/home/zulab/mutants-out/mutants.out/missed.txt"
if [ -f "$MISSED" ] && [ -s "$MISSED" ]; then
  cat "$MISSED" | sed 's/^/    /'
  echo
  echo "  Each line above is a source edit the test suite did NOT notice. These are addressed"
  echo "  individually in the follow-up task, not summarised into a score."
elif [ -f "$MISSED" ]; then
  echo "    NONE. Every viable mutant was caught."
  echo "    Stated with its limit: this means the suite kills every mutation cargo-mutants"
  echo "    knows how to generate for this crate. It does not mean the crate is correct."
  echo "    Mutation operators are syntactic; a wrong SPECIFICATION survives all of them."
  echo "    That gap is what halmos and hevm cover, and why both exist here."
else
  echo "    missed.txt not produced, so the run did not complete. Not reported as a score."
fi

echo
echo "## Verdict, task 1.7"
if [ -f "$MISSED" ]; then
  echo "  RESULT: run completed, survivors listed above (exit $MUT_RC)."
  echo "  cargo-mutants exits non-zero WHEN MUTANTS SURVIVE, so a non-zero exit here is a"
  echo "  finding, not a tool failure. That distinction matters: treating it as a crash"
  echo "  would have thrown away the only interesting output."
else
  echo "  RESULT: INCOMPLETE (exit $MUT_RC). No score claimed."
fi
} | tee -a "$OUT"

echo "written: $OUT"
