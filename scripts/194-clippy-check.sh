#!/usr/bin/env bash
# Clippy, run bare with its exit code captured immediately.
#
# An earlier check reported `exit 0` while the log contained `error: this operation has no effect`.
# An exit code that disagrees with its own log is the least trustworthy signal there is, and a CI
# gate built on it would be a green that cannot go red. So this runs the command with nothing piped
# after it and prints both the status and the error count.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

CARGO="$HOME/.cargo/bin/cargo"
LOG=/tmp/clippy-bare.txt

# --locked so CI and local resolve identical dependency versions.
"$CARGO" clippy --workspace --all-targets --locked -- -D warnings > "$LOG" 2>&1
RC=$?

echo "clippy exit code: $RC"
echo "error lines:      $(grep -c '^error' "$LOG")"
echo
grep -E "^error(\[|:)" "$LOG" | head -10
echo
grep -E "^\s+--> " "$LOG" | sed 's|.*ASML-X/||' | sort -u | head -10
exit "$RC"
