#!/usr/bin/env bash
# Task 6.4: an external agent's accepted quote settles onchain, traceable to its request.
#
# THINKING: #24 game theoretic (the caller is a stranger and the gate must run for them exactly as it
# does for us), #11 systems (two processes, one keystore, and the handoff between them is the design),
# #50 empirical.
#
# WHAT THIS PROVES, and what it deliberately does not. It proves a request from a separate process in
# a different language produced a real transaction on chain 1952 that can be traced back to that
# request by quote id. It does NOT claim an agent framework was used: ADR-012 records why no LLM
# framework sits on this path, and the caller here is a plain HTTP client, which is the point of the
# surface being HTTP.
#
# EVIDENCE PATH declared before code: evidence/phase6/framework-agent.log,
# evidence/phase6/accepted-quotes.jsonl, and the settlement tx hash inside both.
# PASS: a real tx hash traceable to the external agent's request.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

PORT=8737
KEY=demo-agent-key-1
OUT="$REPO/evidence/phase6/framework-agent.log"
ACCEPTED="$REPO/evidence/phase6/accepted-quotes.jsonl"
mkdir -p "$(dirname "$OUT")"

pkill -x asml-coord 2>/dev/null || true
sleep 1
: > "$ACCEPTED"

{
echo "External agent settlement, task 6.4"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## 1. start the coordination API (no keystore, never signs)"
} 2>&1 | tee "$OUT"

ASML_RATE_LIMIT=60 ASML_REPO="$REPO" ASML_COORD_PORT=$PORT setsid nohup \
  ./target/release/asml-coord > /home/zulab/coord-6-4.log 2>&1 < /dev/null &
for i in $(seq 1 180); do
  curl -sS --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
  sleep 1
done
{
echo "  server up after ${i}s (includes the pre-bind book read)"
grep -E "primed|listening|freshness" /home/zulab/coord-6-4.log | sed 's/^/  /'
} | tee -a "$OUT"

{
echo
echo "## 2. the external caller reads the brain's view and sizes its own order"
} | tee -a "$OUT"

CAP=$(curl -s -m 20 -H "x-api-key: $KEY" "http://127.0.0.1:$PORT/capacity")
echo "  GET /capacity -> $CAP" | tee -a "$OUT"
MAXP=$(printf '%s' "$CAP" | grep -oE '"max_permitted_size_micro":"[0-9]+"' | grep -oE '[0-9]+')

# The caller picks its OWN size, a quarter of what it was told it may have. A caller that simply
# echoes back the maximum is not making a decision.
SIZE=$(( ${MAXP:-0} / 4 ))
# Floor of 0.5 unit. When the market is at its cap /capacity correctly reports 0 permitted, and a
# caller still has to name a size to be refused on; this is the size it names.
[ "$SIZE" -lt 500000 ] && SIZE=500000
echo "  caller chooses size_micro=$SIZE (a quarter of the permitted maximum)" | tee -a "$OUT"

{
echo
echo "## 3. request a quote, which passes through the SAME risk gate as an internal decision"
} | tee -a "$OUT"
SIDE=buy
QUOTE=$(curl -s -m 20 -X POST -H "x-api-key: $KEY" -H 'content-type: application/json' \
  -d "{\"size_micro\":\"$SIZE\",\"side\":\"$SIDE\"}" "http://127.0.0.1:$PORT/quote")
echo "  POST /quote side=$SIDE -> $QUOTE" | tee -a "$OUT"
QID=$(printf '%s' "$QUOTE" | grep -oE '"quote_id":[0-9]+' | grep -oE '[0-9]+')

# A refusal is an answer, not a dead end. The per-market cap is currently full from earlier runs, so a
# BUY is refused with its numbers. A real counterparty reacts by taking the side that REDUCES exposure,
# which is what the risk engine is telling it to do. Both halves get exercised in one run.
if [ -z "$QID" ]; then
  echo "  refused on the buy side, which is the gate working. Reason above." | tee -a "$OUT"
  SIDE=sell
  QUOTE=$(curl -s -m 20 -X POST -H "x-api-key: $KEY" -H 'content-type: application/json' \
    -d "{\"size_micro\":\"$SIZE\",\"side\":\"$SIDE\"}" "http://127.0.0.1:$PORT/quote")
  echo "  POST /quote side=$SIDE -> $QUOTE" | tee -a "$OUT"
  QID=$(printf '%s' "$QUOTE" | grep -oE '"quote_id":[0-9]+' | grep -oE '[0-9]+')
fi

if [ -z "$QID" ]; then
  echo "  no quote issued on either side, cannot continue" | tee -a "$OUT"
  exit 1
fi

{
echo
echo "## 4. accept it. The API writes a handoff record and does NOT sign."
} | tee -a "$OUT"
ACC=$(curl -s -m 20 -X POST -H "x-api-key: $KEY" -H 'content-type: application/json' \
  -d "{\"quote_id\":$QID}" "http://127.0.0.1:$PORT/accept")
echo "  POST /accept -> $ACC" | tee -a "$OUT"
echo "  handoff file:" | tee -a "$OUT"
cat "$ACCEPTED" | sed 's/^/    /' | tee -a "$OUT"

{
echo
echo "## 5. the runtime settles it. This process owns the keystore; the API never did."
} | tee -a "$OUT"
timeout 300 ./target/release/asml settle-accepted 2>&1 | sed 's/^/  /' | tee -a "$OUT"

{
echo
echo "## 6. the result, traced back to the caller's request"
} | tee -a "$OUT"
TX=$(grep -oE '"tx_hash":"0x[0-9a-fA-F]+"' "$ACCEPTED" | grep -oE '0x[0-9a-fA-F]+' | head -1)
{
if [ -n "$TX" ]; then
  echo "  quote id:     $QID"
  echo "  tx hash:      $TX"
  echo "  explorer:     https://www.oklink.com/x-layer-testnet/tx/$TX"
  echo "  receipt status: $(cast receipt "$TX" --rpc-url "$XLAYER_TESTNET_RPC" --json 2>/dev/null | grep -oE '"status":"0x[01]"' | head -1)"
  echo
  echo "  journal entry recorded against the quote id:"
  grep "\"decision_id\": *\"\\?$QID\"\\?" "$REPO/evidence/journal.jsonl" | tail -1 | cut -c1-300 | sed 's/^/    /'
  echo
  echo "  RESULT: PASS. A stranger's request produced this transaction, and the quote id ties them."
else
  echo "  RESULT: FAIL. No transaction hash in the handoff record."
  echo "  The refusal or error recorded there is the honest answer:"
  grep -oE '"settle_(refusal|error)":"[^"]*"' "$ACCEPTED" | sed 's/^/    /'
fi
} | tee -a "$OUT"

pkill -x asml-coord 2>/dev/null || true
echo "written: $OUT"
[ -n "$TX" ]
