#!/usr/bin/env bash
# Start the coordination API and wait for it to be ready.
#
# A script file because $REPO does not survive `wsl -c` (E4), and setsid plus nohup because a
# background process started inside a wsl invocation dies when it exits (E12).
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

pkill -x asml-coord 2>/dev/null || true   # E13: -x, never -f
sleep 1

ASML_REPO="$REPO" setsid nohup "$REPO/target/release/asml-coord" \
  > /home/zulab/coord-flow.log 2>&1 < /dev/null &

# The API primes its snapshot cache BEFORE binding, roughly 35 sequential RPC round trips, so poll
# rather than sleep a guessed amount.
WAITED=0
CODE=000
while [ "$WAITED" -lt 120 ]; do
  CODE=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1:8737/health 2>/dev/null)
  [ "$CODE" = "200" ] && break
  sleep 3
  WAITED=$((WAITED + 3))
done

echo "coordination API: $CODE after ${WAITED}s"
[ "$CODE" = "200" ] || tail -6 /home/zulab/coord-flow.log
[ "$CODE" = "200" ]
