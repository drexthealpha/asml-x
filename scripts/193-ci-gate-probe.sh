#!/usr/bin/env bash
# Probe each gate the CI pipeline will run, capturing its REAL exit code.
#
# A pipeline is only as good as the exit codes it gates on. `cargo fmt --all --check` printing 40
# diffs while appearing to exit 0 would make a formatting gate that can never fail, which is exactly
# the "green that cannot go red" this project treats as a defect. So each command is run bare, with
# its status captured immediately and nothing piped after it.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

CARGO="$HOME/.cargo/bin/cargo"
FORGE="$HOME/.foundry/bin/forge"

probe() { # label command...
  local label="$1"; shift
  local rc
  "$@" > "/tmp/gate-$$.log" 2>&1
  rc=$?
  printf "  %-38s exit %-4s %s\n" "$label" "$rc" "$([ "$rc" -eq 0 ] && echo PASS || echo FAIL)"
  if [ "$rc" -ne 0 ]; then
    sed -n '1,6p' "/tmp/gate-$$.log" | sed 's/^/        /'
  fi
  return 0
}

echo "=== rust gates ==="
probe "cargo fmt --all --check" "$CARGO" fmt --all --check
probe "cargo clippy -D warnings" "$CARGO" clippy --workspace --all-targets -- -D warnings
probe "cargo build --workspace" "$CARGO" build --workspace --locked
probe "cargo test --workspace" "$CARGO" test --workspace

echo
echo "=== contract gates ==="
cd "$REPO/contracts"
probe "forge build" "$FORGE" build
probe "forge test" "$FORGE" test --color never
cd "$REPO"

echo
echo "=== evidence gates ==="
probe "chain inventory" python3 scripts/181-repro-inventory.py
probe "claim tags" python3 scripts/187-claim-tags.py

echo
echo "=== frontend gates ==="
cd "$REPO/ui-v2"
probe "pnpm build (tsc -b && vite build)" /home/zulab/.npm-global/bin/pnpm build
cd "$REPO"
