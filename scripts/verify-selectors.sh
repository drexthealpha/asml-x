#!/usr/bin/env bash
# Verify every hand-written function selector in ui-v2/src/lib/vault.ts against `cast sig`.
#
# Hand-encoding calldata is fine as long as the encoding is CHECKED. A wrong selector does not throw:
# it calls a different function or falls through to a fallback, and the UI shows a plausible zero. So
# the signatures are written beside the constants in the source, and this script confirms each one.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

SRC="$REPO/ui-v2/src/lib/vault.ts"
BAD=0

check() {
  local want="$1" sig="$2"
  local got
  got=$(cast sig "$sig" 2>/dev/null)
  if [ "$got" = "$want" ]; then
    printf '  ok    %-40s %s\n' "$sig" "$want"
  else
    printf '  WRONG %-40s source says %s, cast says %s\n' "$sig" "$want" "$got"
    BAD=$((BAD + 1))
  fi
}

echo "== selectors in $SRC =="
check "$(grep -oP 'balanceOf: "\K0x[0-9a-f]{8}' "$SRC")"    "balanceOf(address)"
check "$(grep -oP 'maxNotional: "\K0x[0-9a-f]{8}' "$SRC")"  "maxNotional(address)"
check "$(grep -oP 'paused: "\K0x[0-9a-f]{8}' "$SRC")"       "paused(address)"
check "$(grep -oP 'withdrawable: "\K0x[0-9a-f]{8}' "$SRC")" "withdrawable(address)"
check "$(grep -oP 'committed: "\K0x[0-9a-f]{8}' "$SRC")"    "committed(address)"
check "$(grep -oP 'deposit: "\K0x[0-9a-f]{8}' "$SRC")"      "deposit(uint256,uint256)"
check "$(grep -oP 'withdrawAll: "\K0x[0-9a-f]{8}' "$SRC")"  "withdrawAll()"
check "$(grep -oP 'setPaused: "\K0x[0-9a-f]{8}' "$SRC")"    "setPaused(bool)"
check "$(grep -oP 'approve: "\K0x[0-9a-f]{8}' "$SRC")"      "approve(address,uint256)"
check "$(grep -oP 'allowance: "\K0x[0-9a-f]{8}' "$SRC")"    "allowance(address,address)"
check "$(grep -oP 'feeBps: "\K0x[0-9a-f]{8}' "$SRC")"       "feeBps()"
check "$(grep -oP 'depositWithPermit: "\K0x[0-9a-f]{8}' "$SRC")" \
  "depositWithPermit(uint256,uint256,uint256,uint8,bytes32,bytes32)"
check "$(grep -oP 'nonces: "\K0x[0-9a-f]{8}' "$SRC")"       "nonces(address)"
check "$(grep -oP '  name: "\K0x[0-9a-f]{8}' "$SRC")"       "name()"

echo
echo "wrong selectors: $BAD"
[ "$BAD" -eq 0 ] || exit 1
