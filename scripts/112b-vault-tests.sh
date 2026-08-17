#!/usr/bin/env bash
# Task 8.2 gate. PASS: the agent key cannot withdraw to any address under any input.
#
# The declared-test count is asserted before any pass is trusted, for the same reason task 7.4's gate
# does it: a --match-contract typo produces "0 tests" and exit 0, which reads as green.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase8/vault-tests.txt"
mkdir -p "$(dirname "$OUT")"
cd "$REPO/contracts"

DECLARED=$(grep -cE '^    function test' test/AgentVault.t.sol)

{
  echo "Task 8.2, AgentVault custody suite"
  echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "tests declared in test/AgentVault.t.sol: $DECLARED"
  echo
} > "$OUT"

forge test --match-contract AgentVaultTest -vv >> "$OUT" 2>&1
RC=$?

RAN=$(grep -cE '^\[PASS\] test' "$OUT")
FAILED=$(grep -cE '^\[FAIL' "$OUT")

{
  echo
  echo "== gate =="
  echo "declared: $DECLARED"
  echo "passed:   $RAN"
  echo "failed:   $FAILED"
  echo "exit:     $RC"
  if [ "$RC" -eq 0 ] && [ "$RAN" -eq "$DECLARED" ] && [ "$DECLARED" -gt 0 ] && [ "$FAILED" -eq 0 ]; then
    echo "GATE: PASS  $RAN of $DECLARED, none skipped"
  else
    echo "GATE: FAIL"
  fi
} >> "$OUT"

tail -12 "$OUT"
