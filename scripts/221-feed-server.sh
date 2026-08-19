#!/usr/bin/env bash
# Start the live feed server and the static UI server, both detached.
#
# TWO ENVIRONMENT FACTS ARE LOAD-BEARING HERE:
#
# E12 — a background process started inside `wsl -- bash -c` dies when that invocation exits unless
#       it is started with BOTH setsid and nohup. A server that answers once and is gone thirty
#       seconds later is this, and it wasted a cycle before being recognised.
# E10 — bind 0.0.0.0, never 127.0.0.1. WSL2 has its own network namespace, so a loopback bind is
#       unreachable from the Windows-side browser while curl inside the distro reports 200.
#
# WHY NOT `pkill -x python3`. An earlier version of this script did exactly that and killed the
# static UI server along with the feed server, so the page went blank every time the feeds were
# restarted. Each server is now matched by its own script name.
set -uo pipefail
cd "$(dirname "$0")"

PORT="${FEED_PORT:-8787}"
UI_PORT="${UI_PORT:-4173}"
LOG="/tmp/asml-feed-server.log"
UI_LOG="/tmp/asml-ui.log"
DIST="$(cd .. && pwd)/ui-v2/dist"

# Match on the script name, not on `python3`, so only the intended process is replaced.
pkill -f "feed_server.py" >/dev/null 2>&1 || true
sleep 1

FEED_PORT="$PORT" setsid nohup python3 feed_server.py > "$LOG" 2>&1 < /dev/null &
disown 2>/dev/null || true

if ! pgrep -f "http.server $UI_PORT" >/dev/null 2>&1; then
  ( cd "$DIST" && setsid nohup python3 -m http.server "$UI_PORT" --bind 0.0.0.0 > "$UI_LOG" 2>&1 < /dev/null & )
fi

# The first refresh of every feed has to complete before any endpoint answers with data, and the
# Onchain OS feed makes a few dozen signed calls. Waiting here means the caller sees the real state
# rather than a 503 that looks like a broken server.
echo "waiting for the first refresh of each feed"
for _ in $(seq 1 40); do
  sleep 3
  if curl -s -o /dev/null --max-time 3 -w "%{http_code}" "http://127.0.0.1:$PORT/api/market" | grep -q 200; then
    break
  fi
done

echo
echo "feed  $(curl -s -o /dev/null --max-time 4 -w '%{http_code}' "http://127.0.0.1:$PORT/api/market")  market"
echo "feed  $(curl -s -o /dev/null --max-time 4 -w '%{http_code}' "http://127.0.0.1:$PORT/api/onchainos")  onchainos"
echo "feed  $(curl -s -o /dev/null --max-time 4 -w '%{http_code}' "http://127.0.0.1:$PORT/api/intel")  intel"
echo "ui    $(curl -s -o /dev/null --max-time 4 -w '%{http_code}' "http://127.0.0.1:$UI_PORT/")"
echo
tail -6 "$LOG"
