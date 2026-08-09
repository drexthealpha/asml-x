#!/usr/bin/env bash
# Task 2.1: build the workspace, run the property tests, and record versions.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$PATH"
cd "$REPO"

echo "=== toolchain ==="
rustc --version
cargo --version

echo
echo "=== fmt check ==="
cargo fmt --all -- --check 2>&1 | tail -20 || echo "(fmt differences above)"

echo
echo "=== build ==="
cargo build --workspace 2>&1 | tail -40

echo
echo "=== test ==="
cargo test --workspace 2>&1 | tail -60

echo
echo "=== clippy ==="
cargo clippy --workspace --all-targets 2>&1 | tail -30
