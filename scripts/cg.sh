#!/usr/bin/env bash
# Thin cargo wrapper so ~/.cargo/bin is on PATH (lib.sh does it). Args pass straight through.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"
cargo "$@"
