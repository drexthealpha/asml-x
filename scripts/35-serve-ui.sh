#!/usr/bin/env bash
# Serve the UI over HTTP so a judge can open it in a normal browser.
#
# Static server only: the page is a single HTML file that fetches three JSON files from
# the repo. python3's http.server is already present, so no dependency is added for this.
#
#   http://127.0.0.1:8080/ui/                 the dashboard
#   http://127.0.0.1:8080/ui/nodata-check/    the same page with no data files reachable,
#                                             which is the proof it cannot fake data
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
PORT="${1:-8080}"
cd "$REPO"
echo "serving $REPO on http://127.0.0.1:$PORT"
echo "  dashboard      http://127.0.0.1:$PORT/ui/"
echo "  no-data proof  http://127.0.0.1:$PORT/ui/nodata-check/"
echo "Ctrl-C to stop."
exec python3 -m http.server "$PORT" --bind 127.0.0.1
