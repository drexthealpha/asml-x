#!/usr/bin/env bash
# Run the coordination binary in the foreground for a few seconds and print what it says.
#
# The suite's server.log kept showing a banner WITHOUT the priming line even after a rebuild that
# strings(1) confirms contains "priming". Either the suite launches a different binary or the log is
# not what I think it is, and guessing between those is how the last hour went. This prints the
# banner from the exact path the suite uses.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

pkill -9 -x asml-coord 2>/dev/null || true
sleep 1

echo "== binary =="
ls -la --time-style=+%F_%H:%M:%S ./target/release/asml-coord
echo "  contains 'priming': $(strings ./target/release/asml-coord | grep -c priming)"
echo "  contains 'refresher': $(strings ./target/release/asml-coord | grep -c refresher)"
echo
echo "== banner, 45 second run =="
ASML_COORD_PORT=8739 timeout 45 ./target/release/asml-coord > /home/zulab/banner.log 2>&1
echo "exit: $?"
cat /home/zulab/banner.log
