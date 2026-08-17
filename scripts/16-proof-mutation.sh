#!/usr/bin/env bash
# Task 3.2.4: prove the proofs can fail.
#
# A symbolic run that passes is worth nothing until you have watched it catch a
# real violation. This injects one, confirms halmos FAILS, restores, and confirms
# it passes again. R7 applied at the proof level.
#
# Three real defects were found writing this, all of which made a broken run look
# like a passing one. They are documented here so they are never reintroduced:
#   1. halmos colours its output, so `grep '^\[FAIL\]'` never matches. Strip ANSI.
#   2. halmos shells out to `forge`, so forge must be on ITS PATH.
#   3. halmos reads the solidity AST from build artifacts. A plain `forge build`
#      writes artifacts without an AST, halmos then skips every file with
#      "KeyError: 'ast'", finds no tests, and exits quietly. foundry.toml now sets
#      ast = true, and assert_ran refuses to draw conclusions from an empty run.

# SOLVER TIMEOUT IS FINITE. This script used `--solver-timeout-assertion 0`, which is unlimited, and
# a single stalling theorem then produces no output until something else kills it. 240000 ms is the
# value scripts/104b-fee-formal.sh and scripts/112e-vault-formal.sh already use, so every theorem
# script in the repo now fails in bounded time instead of hanging.

set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
if [ -f "$HOME/.asml-venv/bin/activate" ]; then . "$HOME/.asml-venv/bin/activate"; fi

export PATH="$HOME/.foundry/bin:$HOME/.local/bin:$PATH"
command -v forge  >/dev/null || { echo "forge not on PATH, abort";  exit 1; }
command -v halmos --solver yices >/dev/null || { echo "halmos --solver yices not on PATH, abort"; exit 1; }

cd "$REPO/contracts"

G="src/RiskGuard.sol"
BAK="$HOME/.asml-proof-riskguard.sol"
EVID="$REPO/evidence/formal"
mkdir -p "$EVID"
cp "$G" "$BAK"
restore() { cp "$BAK" "$G"; }
trap restore EXIT

strip_ansi() { sed -r 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

run_halmos() {
  touch "$G"
  timeout 900 halmos --solver yices --contract RiskGuardSymbolic --solver-timeout-assertion 240000 \
    > "$EVID/raw-$1.txt" 2>&1
  strip_ansi < "$EVID/raw-$1.txt" > "$EVID/clean-$1.txt"
}

assert_ran() {
  if grep -q 'No tests with' "$EVID/clean-$1.txt"; then
    echo "HALMOS FOUND NO TESTS in run '$1'. Every conclusion would be void. Abort."
    tail -4 "$EVID/clean-$1.txt"
    exit 1
  fi
  if ! grep -q 'Symbolic test result' "$EVID/clean-$1.txt"; then
    echo "HALMOS PRODUCED NO RESULT LINE in run '$1'. Abort."
    tail -6 "$EVID/clean-$1.txt"
    exit 1
  fi
}

echo "=== 1. baseline: all proofs must PASS ==="
run_halmos baseline
assert_ran baseline
grep -E 'Symbolic test result' "$EVID/clean-baseline.txt" | tail -1
BASE_FAILED=$(grep -oE '[0-9]+ failed' "$EVID/clean-baseline.txt" | tail -1 | awk '{print $1}')
if [ "${BASE_FAILED:-1}" != "0" ]; then
  echo "BASELINE IS NOT CLEAN. Abort before drawing conclusions."
  exit 1
fi
cp "$EVID/clean-baseline.txt" "$EVID/halmos-riskguard.txt"

echo
echo "=== 2. inject a real violation: loosen the market cap check by 1 wei ==="
sed -i 's|if (nextMarket > cap) revert MarketCapExceeded(market, nextMarket, cap);|if (nextMarket > cap + 1) revert MarketCapExceeded(market, nextMarket, cap);|' "$G"
grep -q 'cap + 1' "$G" || { echo "sed did not apply, abort"; exit 1; }

run_halmos mutated
assert_ran mutated
grep -E '^\[FAIL\]|Symbolic test result' "$EVID/clean-mutated.txt" | head -10
MUT_FAILED=$(grep -oE '[0-9]+ failed' "$EVID/clean-mutated.txt" | tail -1 | awk '{print $1}')
cp "$EVID/clean-mutated.txt" "$EVID/halmos-injected-violation.txt"

if [ "${MUT_FAILED:-0}" != "0" ]; then
  echo "RESULT: the prover CAUGHT the injected violation ($MUT_FAILED proof(s) failed)."
  CAUGHT=yes
else
  echo "RESULT: the prover MISSED a real violation. The proofs prove nothing."
  CAUGHT=no
fi

echo
echo "=== 3. restore and confirm PASS again ==="
restore
run_halmos restored
assert_ran restored
grep -E 'Symbolic test result' "$EVID/clean-restored.txt" | tail -1
REST_FAILED=$(grep -oE '[0-9]+ failed' "$EVID/clean-restored.txt" | tail -1 | awk '{print $1}')

cat > "$REPO/docs/decisions/ADR-007-formal-verification-tool.md" <<MD
# ADR-007: Halmos, not CertoraProver

Date 9 Aug 2026. Status ACCEPTED. Task 3.1.

## Context
The plan mandated CertoraProver for the risk and kill-switch logic. It is GPLv3
and documented as locally runnable, but the local route is a JVM build with a
Python venv and pinned solc versions, while the supported route is their cloud
service.

## Decision
Use Halmos for the symbolic proofs. R16 applied before getting stuck rather than
after: Halmos is a pip install, runs fully locally with no key, reads ordinary
Solidity so the proofs sit beside the Foundry tests, and targets exactly the class
of property ADR-006 needs.

## Evidence it is sufficient
Seven theorems over RiskGuard, each proven for ALL inputs in the declared ranges
rather than sampled: per-market cap over any two adds, gross cap across two
markets, killed blocks every add for any amount, only-owner revive over a symbolic
caller address, only-owner cap raise, gross always equals sum of parts across
add/add/reduce, and unconfigured markets failing closed for any market id.
Output: evidence/formal/halmos-riskguard.txt

## Proof that the proofs can fail
Injected violation: the per-market cap check loosened by one wei.
Prover caught it: **$CAUGHT** ($MUT_FAILED proof(s) failed under mutation,
$REST_FAILED after restore).
Output: evidence/formal/halmos-injected-violation.txt

## Cost, stated plainly
Certora's CVL is more expressive for multi-contract and parametric rules, and a
Certora report carries more weight with auditors. The theorems here are written as
pre and post conditions rather than in Halmos-specific idiom, so they translate if
a Certora run is wanted later. This substitution is disclosed in the README, not
glossed over.
MD

echo
echo "ADR-007 written. caught=$CAUGHT mutated_failures=$MUT_FAILED restored_failures=$REST_FAILED"
