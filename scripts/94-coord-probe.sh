#!/usr/bin/env bash
# Probe the rewritten coordination API directly: start it, hit each endpoint, and time the burst.
#
# E12: a background process started inside a `wsl -- bash -c` invocation dies when that invocation
# exits unless it is detached with setsid. The probe therefore lives in a script file and starts the
# server itself, rather than relying on a server started by an earlier command.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

PORT="${ASML_COORD_PORT:-8737}"
KEY="demo-agent-key-1"

pkill -x asml-coord 2>/dev/null || true
sleep 1
ASML_RATE_LIMIT="${ASML_RATE_LIMIT:-20}" setsid nohup ./target/release/asml-coord \
  > /home/zulab/coord.log 2>&1 < /dev/null &
sleep 45

echo "== listening =="
ss -ltn | grep ":$PORT" || echo "  NOT LISTENING"
echo
echo "== server banner =="
head -8 /home/zulab/coord.log

echo
echo "== single requests =="
for ep in /health /thesis /capacity; do
  code=$(curl -s -m 25 -o /home/zulab/coord-resp.json -w '%{http_code} %{time_total}s' \
    -H "x-api-key: $KEY" "http://127.0.0.1:$PORT$ep")
  printf '  %-10s %s\n' "$ep" "$code"
  head -c 160 /home/zulab/coord-resp.json 2>/dev/null | sed 's/^/    /'
  echo
done

echo
echo "== 40 request burst, the case that stalled the previous server =="
START=$(date +%s.%N)
CODES=$(for i in $(seq 1 40); do
  curl -s -m 20 -o /dev/null -w '%{http_code} ' -H "x-api-key: $KEY" \
    "http://127.0.0.1:$PORT/thesis"
done)
END=$(date +%s.%N)
echo "  codes: $CODES"
echo "  elapsed: $(echo "$END - $START" | bc)s"
echo
echo "  code histogram:"
echo "$CODES" | tr ' ' '\n' | grep -E '^[0-9]{3}$' | sort | uniq -c | sed 's/^/    /'

echo
echo "== still alive after the burst? =="
curl -s -m 10 -o /dev/null -w '  /health after burst: %{http_code} in %{time_total}s\n' \
  "http://127.0.0.1:$PORT/health"
