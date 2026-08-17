#!/usr/bin/env bash
# Thin forge wrapper so foundry is on PATH (lib.sh does it). Args pass straight through.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO/contracts"
forge "$@"
