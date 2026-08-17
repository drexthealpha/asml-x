#!/usr/bin/env bash
# Verify the EIP-712 typehash constants in MockERC20 against `cast keccak`.
#
# Same reasoning as scripts/verify-selectors.sh, where five of eleven hand-written selectors were
# wrong. A wrong typehash does not throw either: `ecrecover` returns a DIFFERENT address, the permit
# reverts with InvalidSignature, and the failure looks like a bad signature from the wallet rather
# than a bad constant in the contract. That is a long debugging session waiting to happen, and one
# `cast keccak` call prevents it.
#
# The strings are the EIP-2612 and EIP-712 definitions exactly. A single character out, including
# spacing, produces a different hash and an incompatible token.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

SRC="$REPO/contracts/src/MockERC20.sol"
BAD=0

check() {
  local name="$1" want="$2" str="$3"
  local got
  got=$(cast keccak "$str")
  if [ "$got" = "$want" ]; then
    printf '  ok    %-18s %s\n' "$name" "$want"
  else
    printf '  WRONG %-18s source %s\n                     cast   %s\n' "$name" "$want" "$got"
    BAD=$((BAD + 1))
  fi
}

PT=$(grep -A1 'bytes32 public constant PERMIT_TYPEHASH' "$SRC" | grep -oE '0x[0-9a-f]{64}')
DT=$(grep -A1 'bytes32 private constant DOMAIN_TYPEHASH' "$SRC" | grep -oE '0x[0-9a-f]{64}')

echo "== EIP-712 typehashes in $SRC =="
check PERMIT_TYPEHASH "$PT" \
  "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
check DOMAIN_TYPEHASH "$DT" \
  "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"

echo
echo "wrong typehashes: $BAD"
[ "$BAD" -eq 0 ] || exit 1
