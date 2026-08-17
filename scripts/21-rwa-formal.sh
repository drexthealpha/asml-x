#!/usr/bin/env bash
# Phase 5 formal verification, plus the proof-mutation gate for the RWA guard.

# SOLVER TIMEOUT IS FINITE. This script used `--solver-timeout-assertion 0`, which is unlimited, and
# a single stalling theorem then produces no output until something else kills it. 240000 ms is the
# value scripts/104b-fee-formal.sh and scripts/112e-vault-formal.sh already use, so every theorem
# script in the repo now fails in bounded time instead of hanging.

set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.foundry/bin:$HOME/.local/bin:$PATH"
command -v halmos >/dev/null || { echo "halmos missing"; exit 1; }
cd "$REPO/contracts"

EVID="$REPO/evidence/formal"
mkdir -p "$EVID"
G="src/RwaRiskGuard.sol"
BAK="$HOME/.asml-proof-rwaguard.sol"
cp "$G" "$BAK"
restore() { cp "$BAK" "$G"; }
trap restore EXIT

strip_ansi() { sed -r 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

run() {
  touch "$G"
  timeout 900 halmos --contract RwaRiskGuardSymbolic --solver-timeout-assertion 240000 \
    > "$EVID/raw-rwa-$1.txt" 2>&1
  strip_ansi < "$EVID/raw-rwa-$1.txt" > "$EVID/clean-rwa-$1.txt"
}

assert_ran() {
  grep -q 'No tests with' "$EVID/clean-rwa-$1.txt" && { echo "NO TESTS FOUND in $1, abort"; exit 1; }
  grep -q 'Symbolic test result' "$EVID/clean-rwa-$1.txt" || { echo "NO RESULT LINE in $1, abort"; tail -6 "$EVID/clean-rwa-$1.txt"; exit 1; }
}

echo "=== 1. baseline ==="
run baseline; assert_ran baseline
grep -E '^\[PASS\]|^\[FAIL\]|Symbolic test result' "$EVID/clean-rwa-baseline.txt"
BASE_FAILED=$(grep -oE '[0-9]+ failed' "$EVID/clean-rwa-baseline.txt" | tail -1 | awk '{print $1}')
if [ "${BASE_FAILED:-1}" != "0" ]; then echo "BASELINE NOT CLEAN, abort"; exit 1; fi
cp "$EVID/clean-rwa-baseline.txt" "$EVID/halmos-rwa-guard.txt"

echo
echo "=== 2. inject a violation: drop the issuer-pause refusal ==="
sed -i 's|if (isPaused) {\n            emit RwaRefusal(market, "issuer paused");\n            revert IssuerPaused();\n        }||' "$G"
# Multi-line sed is unreliable, so neutralise the condition instead.
sed -i '0,/if (isPaused) {/{s|if (isPaused) {|if (false \&\& isPaused) {|}' "$G"
grep -q 'if (false && isPaused)' "$G" || { echo "sed did not apply, abort"; exit 1; }

run mutated; assert_ran mutated
grep -E '^\[FAIL\]|Symbolic test result' "$EVID/clean-rwa-mutated.txt" | head -8
MUT_FAILED=$(grep -oE '[0-9]+ failed' "$EVID/clean-rwa-mutated.txt" | tail -1 | awk '{print $1}')
cp "$EVID/clean-rwa-mutated.txt" "$EVID/halmos-rwa-injected-violation.txt"

if [ "${MUT_FAILED:-0}" != "0" ]; then
  echo "RESULT: prover CAUGHT the removed pause refusal ($MUT_FAILED failed)."
  CAUGHT=yes
else
  echo "RESULT: prover MISSED it. The RWA proofs prove nothing."
  CAUGHT=no
fi

echo
echo "=== 3. restore ==="
restore; run restored; assert_ran restored
grep -E 'Symbolic test result' "$EVID/clean-rwa-restored.txt"

echo
echo "caught=$CAUGHT"
