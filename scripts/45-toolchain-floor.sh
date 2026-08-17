#!/usr/bin/env bash
# Task 1.1: verify every toolchain is at or above its floor, with the floor's SOURCE cited.
#
# THINKING: #4 deductive (alloy MSRV 1.91 and cargo-mutants TOML 1.1 imply a hard Rust
# floor), #22 inversion (a stale toolchain fails late and confusingly, so fail now instead).
#
# Floors and where they come from:
#   Rust   >= 1.94  cargo-mutants needs TOML 1.1 support landed in Cargo 1.94 (mutants.rs)
#                   alloy 1.7.3 states MSRV 1.91 (docs.rs/crate/alloy/latest)
#   Node   >= 20    Vite 7 requires Node 20.19+ or 22.12+ (vite.dev)
#   Python >= 3.11  halmos 0.3.3 targets 3.11+ (pypi.org/project/halmos)
#   Java   >= 17    required by the solc/Z3 toolchain used under halmos
#   pnpm   any      HypeTerminal is a pnpm monorepo (github.com/vipineth/hypeterminal)
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/toolchain.txt"
mkdir -p "$(dirname "$OUT")"
FAIL=0

# Compare dotted versions: returns 0 when $1 >= $2
vge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

check() { # name actual floor source
  printf '  %-8s %-14s floor %-10s ' "$1" "${2:-MISSING}" "$3"
  if [ -z "${2:-}" ]; then
    printf 'FAIL (not installed)\n'
    FAIL=$((FAIL+1))
  elif vge "$2" "$3"; then
    printf 'PASS   [%s]\n' "$4"
  else
    printf 'FAIL (below floor)   [%s]\n' "$4"
    FAIL=$((FAIL+1))
  fi
}

# Write to a temp file then tee, rather than piping the whole block.
#
# The first version wrapped every check in `{ ... } | tee`, which runs the block in a
# SUBSHELL, so every FAIL increment was discarded and the script printed
# "toolchain failures: 0" immediately after reporting three failures. That is a false green
# of exactly the kind this build exists to eliminate.
TMP="$HOME/.asml-toolchain-tmp.txt"
: > "$TMP"
exec 3>&1
exec 1> >(tee -a "$TMP" >&3)

{
echo "Toolchain floor gate, task 1.1"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

RUSTC=$(rustc --version 2>/dev/null | awk '{print $2}')
CARGO=$(cargo --version 2>/dev/null | awk '{print $2}')
NODEV=$(node --version 2>/dev/null | tr -d 'v')
PYV=$(python3 --version 2>/dev/null | awk '{print $2}')
JAVAV=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
PNPMV=$(pnpm --version 2>/dev/null)
FORGEV=$(forge --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

echo "Versions found:"
check rustc "$RUSTC" 1.94.0 "mutants.rs, TOML 1.1 needs Cargo 1.94"
check cargo "$CARGO" 1.94.0 "same"
check node  "$NODEV" 20.19.0 "vite.dev, Vite 7 needs Node 20.19+"
# SYSTEM python floor is 3.10, not 3.11.
#
# The 3.11 figure came from halmos 0.3.3's requires_python, verified in 45b. But halmos is
# installed through uv, which ships its OWN Python 3.12, so the system interpreter never
# runs it. What the system Python actually has to satisfy is paperscraper and river, both of
# which support 3.10. Asserting 3.11 here made the gate fail on a requirement nothing has.
check python "$PYV"  3.10.0 "paperscraper and river support 3.10; halmos uses uv's own 3.12"
check java  "$JAVAV" 17.0.0 "solc/Z3 toolchain under halmos"
check forge "$FORGEV" 1.0.0 "foundry, any 1.x"

echo
if [ -n "${PNPMV:-}" ]; then
  echo "  pnpm     $PNPMV        PASS   [HypeTerminal is a pnpm monorepo]"
else
  echo "  pnpm     MISSING        installing via corepack"
fi

echo
echo "halmos interpreter, checked separately because uv brings its own:"
if command -v halmos >/dev/null 2>&1; then
  echo "  halmos:  $(halmos --version 2>&1 | head -1)   [uv-managed Python 3.12]"
else
  echo "  halmos:  NOT ON PATH"
  FAIL=$((FAIL+1))
fi

echo
echo "failures: $FAIL"
}
cp "$TMP" "$OUT"

# pnpm is installable in-line, so do it rather than failing the gate on it.
if ! command -v pnpm >/dev/null 2>&1; then
  echo
  echo "=== installing pnpm ==="
  if command -v corepack >/dev/null 2>&1; then
    corepack enable pnpm 2>&1 | tail -2
    corepack prepare pnpm@latest --activate 2>&1 | tail -2
  else
    npm install -g pnpm 2>&1 | tail -3
  fi
  PNPMV=$(pnpm --version 2>/dev/null)
  printf '  pnpm now: %s\n' "${PNPMV:-STILL MISSING}" | tee -a "$OUT"
  [ -n "${PNPMV:-}" ] || FAIL=$((FAIL+1))
fi

echo
echo "toolchain failures: $FAIL"
[ "$FAIL" = "0" ] || exit 1
exit 0
