#!/usr/bin/env bash
# Phase 3, tasks 3.1 and 3.2: formal verification of the risk guard.
#
# R16 applied up front rather than after getting stuck. CertoraProver is a large
# JVM build whose local path is documented as "clone, venv, certoraRun.py" but
# whose cloud service is the supported route. Halmos is a pip install that runs
# fully locally with no key, targets exactly the same class of property, and reads
# ordinary Solidity. So Halmos is attempted FIRST as the cheap certain path, and
# Certora is only attempted if Halmos cannot express what we need.
# The choice is recorded in docs/decisions/ADR-007-formal-verification-tool.md.

# SOLVER TIMEOUT IS FINITE. This script used `--solver-timeout-assertion 0`, which is unlimited, and
# a single stalling theorem then produces no output until something else kills it. 240000 ms is the
# value scripts/104b-fee-formal.sh and scripts/112e-vault-formal.sh already use, so every theorem
# script in the repo now fails in bounded time instead of hanging.

set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
EVID="$REPO/evidence/formal"
mkdir -p "$EVID"

VENV="$HOME/.asml-venv"
if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
fi
. "$VENV/bin/activate"

if ! command -v halmos --solver yices >/dev/null 2>&1; then
  echo "=== installing halmos --solver yices (local, no cloud key) ==="
  pip install --quiet --upgrade pip
  pip install --quiet halmos --solver yices 2>&1 | tail -5
fi
echo "halmos: $(halmos --version 2>&1 | head -1)"
echo "z3: $(python3 -c 'import z3; print(z3.get_version_string())' 2>&1 | head -1)"

cd "$REPO/contracts"
echo
echo "=== forge build (halmos --solver yices consumes forge artifacts) ==="
forge build 2>&1 | tail -3

echo
echo "=== proving RiskGuardSymbolic ==="
timeout 900 halmos --solver yices --contract RiskGuardSymbolic --solver-timeout-assertion 240000 2>&1 | tee "$EVID/halmos-riskguard.txt" | tail -40

echo
echo "=== summary ==="
grep -cE '^\[PASS\]' "$EVID/halmos-riskguard.txt" 2>/dev/null | sed 's/^/passed: /' || true
grep -cE '^\[FAIL\]' "$EVID/halmos-riskguard.txt" 2>/dev/null | sed 's/^/failed: /' || true
