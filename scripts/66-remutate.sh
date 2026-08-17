#!/usr/bin/env bash
# Task 1.7 close-out. Run the new tests, then re-run cargo-mutants and compare survivor counts.
# The claim being tested is not "tests pass", it is "the 37 mutants that survived are dead".
#
# THINKING: #60 falsifiability (the missed list IS the score, so it is compared before and
# after), #22 inversion.
#
# EVIDENCE PATH: evidence/phase0/cargo-mutants-after.txt plus the diff below.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

OUT="$REPO/evidence/phase0/cargo-mutants-after.txt"
BEFORE="/home/zulab/mutants-missed-before.txt"
cp /home/zulab/mutants-out2/mutants.out/missed.txt "$BEFORE" 2>/dev/null || : > "$BEFORE"

{
echo "Mutation close-out, task 1.7"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Step 1: do the new tests even pass?"
} 2>&1 | tee "$OUT"

timeout 1200 cargo test -p risk-engine 2>&1 | tail -30 | sed 's/^/  /' | tee -a "$OUT"
TEST_RC=${PIPESTATUS[0]}

{
echo
echo "## Step 2: clippy, because these tests are new code under a strict lint set"
} | tee -a "$OUT"
timeout 900 cargo clippy -p risk-engine --all-targets -- -D warnings 2>&1 \
  | tail -20 | sed 's/^/  /' | tee -a "$OUT"
CLIPPY_RC=${PIPESTATUS[0]}

if [ "${TEST_RC:-1}" -ne 0 ] || [ "${CLIPPY_RC:-1}" -ne 0 ]; then
  {
  echo
  echo "## STOPPING before re-mutation"
  echo "  tests exit $TEST_RC, clippy exit $CLIPPY_RC. Re-running cargo-mutants against a"
  echo "  suite that does not compile or does not pass would produce a meaningless survivor"
  echo "  count, and a meaningless number in an evidence file is worse than no number."
  } | tee -a "$OUT"
  exit 1
fi

{
echo
echo "## Step 3: re-mutate and compare"
echo "  survivors BEFORE: $(wc -l < "$BEFORE")"
} | tee -a "$OUT"

BACKUP="/home/zulab/risk-engine-src-backup3"
rm -rf "$BACKUP"; mkdir -p "$BACKUP"
cp -r crates/risk-engine/src "$BACKUP/src"
restore() {
  rm -rf crates/risk-engine/src
  cp -r "$BACKUP/src" crates/risk-engine/src
  echo "  source restored" | tee -a "$OUT"
}
trap restore EXIT

timeout 5400 cargo mutants -p risk-engine --in-place --timeout 90 \
  --output /home/zulab/mutants-out3 2>&1 | tail -25 | sed 's/^/  /' | tee -a "$OUT"

AFTER="/home/zulab/mutants-out3/mutants.out/missed.txt"
{
echo
echo "## Result"
if [ -f "$AFTER" ]; then
  echo "  survivors AFTER:  $(wc -l < "$AFTER")"
  echo "  caught AFTER:     $(wc -l < /home/zulab/mutants-out3/mutants.out/caught.txt 2>/dev/null || echo '?')"
  echo
  echo "  Mutants that were killed by the new tests:"
  comm -23 <(sort "$BEFORE") <(sort "$AFTER") | sed 's/^/    KILLED  /'
  echo
  echo "  Mutants that STILL survive, which is the honest remainder:"
  comm -13 <(sort "$BEFORE") <(sort "$AFTER") | sed 's/^/    NEW     /'
  comm -12 <(sort "$BEFORE") <(sort "$AFTER") | sed 's/^/    STILL   /'
else
  echo "  re-mutation did not complete, no count claimed"
fi
} | tee -a "$OUT"

echo "written: $OUT"
