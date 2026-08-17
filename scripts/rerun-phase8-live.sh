#!/usr/bin/env bash
# Re-run every Phase 8 LIVE gate against the redeployed contracts.
#
# ADR-017 changed MockERC20 and AgentVault, so both were redeployed. A Phase 9 convenience is not
# allowed to silently invalidate a Phase 8 proof: the gates that ran against the old bytecode say
# nothing about the new bytecode, and the claims C-802, C-805 and C-806 are about the deployed
# contracts rather than about the source.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

PASS=0
FAIL=0

run() {
  echo
  echo "=== $1 ==="
  local v
  v=$(bash "./$1" < /dev/null 2>&1 | grep -E '^GATE:' | tail -1)
  echo "${v:-NO GATE LINE}"
  case "$v" in
    "GATE: PASS"*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)) ;;
  esac
}

run 112b-vault-tests.sh
run 112d-per-user-limits.sh
run 113-vault-live.sh
run 114-pause-under-load.sh

echo
echo "=== phase 8 live gates on the redeployed bytecode ==="
echo "pass: $PASS  fail: $FAIL"
[ "$FAIL" -eq 0 ]
