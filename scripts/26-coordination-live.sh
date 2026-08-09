#!/usr/bin/env bash
# Phase 6 live proof: start the coordination API, run the EXTERNAL Python agent in its
# own process, capture both logs.
#
# The named fake win was "the second agent is a button in our own UI calling an internal
# function". So: two processes, two languages, HTTP between them, and the server's own
# log shown alongside the client's.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$PATH"

EVID="$REPO/evidence/coordination"
mkdir -p "$EVID"
PORT=8737

cd "$REPO"
cargo build --release -p coordination-api 2>&1 | tail -1

# Make sure nothing is already bound.
pkill -f 'asml-coord' 2>/dev/null || true
sleep 1

echo "=== starting the coordination API in its own process ==="
# Rate limit shrunk for the run so the limiter can be OBSERVED tripping rather than
# assumed to work. With the default 30 per minute and seconds-long chain reads, a burst
# outlasts the 60 second window and the count never accumulates. Verifying the mechanism
# means shrinking the budget, not padding the test.
ASML_RATE_LIMIT="${ASML_RATE_LIMIT:-20}" \
ASML_REPO="$REPO" ASML_COORD_PORT=$PORT ./target/release/asml-coord \
  > "$EVID/server.log" 2>&1 &
SERVER_PID=$!
echo "server pid $SERVER_PID, log $EVID/server.log"

cleanup() { kill "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT

# Wait for it to bind rather than sleeping blindly.
for i in $(seq 1 30); do
  if curl -sS --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    echo "server is up after ${i}s"
    break
  fi
  sleep 1
done

if ! curl -sS --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "SERVER DID NOT START"
  cat "$EVID/server.log"
  exit 1
fi

echo
echo "=== server startup banner ==="
cat "$EVID/server.log"

echo
echo "=== running the EXTERNAL PYTHON AGENT (separate process, separate language) ==="
# python3 -u: unbuffered. Piped through tee, Python block-buffers stdout, so a run in
# progress looks like an empty log and a hang looks identical to a slow success. -u
# makes the log readable while it runs.
ASML_COORD="http://127.0.0.1:$PORT" python3 -u "$REPO/agents/external_agent.py" \
  2>&1 | tee "$EVID/external-agent.log"
AGENT_RC=${PIPESTATUS[0]}

echo
echo "=== server log after the run ==="
tail -20 "$EVID/server.log"

echo
echo "external agent exit code: $AGENT_RC (0 means every expectation held)"
echo "logs: $EVID/server.log and $EVID/external-agent.log"
exit "$AGENT_RC"
