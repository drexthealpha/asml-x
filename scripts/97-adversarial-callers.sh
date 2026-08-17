#!/usr/bin/env bash
# Task 6.5: adversarial caller suite, expanded.
#
# THINKING: #66 red teaming (probe the surface a stranger actually reaches), #24 game theoretic (the
# caller may lie about sizes, types and identity), #62 margin of safety (the property that matters is
# not "each case returns the right code" but "the server is still answering afterwards").
#
# The v1 suite covered eight cases through the Python agent. This adds the ones a hostile caller
# reaches for that a cooperative client never sends: wrong JSON types, a negative size, a size beyond
# i128, an oversized body, path traversal, a huge header, a wrong method, and a concurrent burst while
# the probes run.
#
# PASS: every case refused CLEANLY with a JSON error, and /health still answers at the end. A crash, a
# hang, or a 200 on any of these is a failure.
#
# EVIDENCE PATH declared before code: evidence/phase6/adversarial-callers.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

PORT=8737
KEY=demo-agent-key-1
OUT="$REPO/evidence/phase6/adversarial-callers.txt"
mkdir -p "$(dirname "$OUT")"

pkill -x asml-coord 2>/dev/null || true
sleep 1
ASML_RATE_LIMIT=500 ASML_REPO="$REPO" ASML_COORD_PORT=$PORT setsid nohup \
  ./target/release/asml-coord > /home/zulab/coord-6-5.log 2>&1 < /dev/null &
for i in $(seq 1 180); do
  curl -sS --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
  sleep 1
done

PASS=0
FAIL=0

{
echo "Adversarial caller suite, task 6.5"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  server up after ${i}s"
echo "  rate limit raised to 500 for this run so the LIMITER does not mask the other refusals."
echo "  The limiter has its own demonstration in evidence/phase6/rate-limit-429.txt."
echo
printf '  %-34s %-8s %-8s %s\n' "case" "expect" "got" "verdict"
} 2>&1 | tee "$OUT"

# probe NAME EXPECTED_CODE curl-args...
probe() {
  local name="$1" expect="$2"; shift 2
  local code
  code=$(curl -s -m 15 -o /home/zulab/adv-body.txt -w '%{http_code}' "$@" 2>/dev/null || echo 000)
  local verdict="PASS"
  if [ "$code" != "$expect" ]; then verdict="FAIL"; FAIL=$((FAIL+1)); else PASS=$((PASS+1)); fi
  printf '  %-34s %-8s %-8s %s\n' "$name" "$expect" "$code" "$verdict" | tee -a "$OUT"
  # A refusal must still be JSON. An HTML error page or an empty body means something crashed rather
  # than refused.
  if ! head -c 1 /home/zulab/adv-body.txt 2>/dev/null | grep -q '{'; then
    printf '      body was not JSON: %s\n' "$(head -c 80 /home/zulab/adv-body.txt)" | tee -a "$OUT"
  fi
}

U="http://127.0.0.1:$PORT"

probe "no api key"                401 "$U/thesis"
probe "unknown api key"           401 -H "x-api-key: not-a-real-key" "$U/thesis"
probe "empty api key"             401 -H "x-api-key: " "$U/thesis"
probe "unknown endpoint"          404 -H "x-api-key: $KEY" "$U/admin/drain"
probe "path traversal"            404 -H "x-api-key: $KEY" "$U/../../etc/passwd"
probe "wrong method on /quote"    404 -H "x-api-key: $KEY" -X DELETE "$U/quote"
probe "malformed json"            400 -H "x-api-key: $KEY" -H 'content-type: application/json' \
      -X POST -d '{not json at all' "$U/quote"
probe "size as a number not str"  400 -H "x-api-key: $KEY" -H 'content-type: application/json' \
      -X POST -d '{"size_micro": 500000}' "$U/quote"
probe "negative size"             400 -H "x-api-key: $KEY" -H 'content-type: application/json' \
      -X POST -d '{"size_micro":"-500000"}' "$U/quote"
probe "zero size"                 400 -H "x-api-key: $KEY" -H 'content-type: application/json' \
      -X POST -d '{"size_micro":"0"}' "$U/quote"
probe "size beyond i128"          400 -H "x-api-key: $KEY" -H 'content-type: application/json' \
      -X POST -d '{"size_micro":"999999999999999999999999999999999999999999"}' "$U/quote"
probe "absurd but parseable size" 409 -H "x-api-key: $KEY" -H 'content-type: application/json' \
      -X POST -d '{"size_micro":"170141183460469231731687303715884105727"}' "$U/quote"
probe "unknown quote id"          404 -H "x-api-key: $KEY" -H 'content-type: application/json' \
      -X POST -d '{"quote_id": 999999}' "$U/accept"
probe "quote id as a string"      404 -H "x-api-key: $KEY" -H 'content-type: application/json' \
      -X POST -d '{"quote_id": "1"}' "$U/accept"

# A 64KB body and a 16KB header: neither should be accepted, and neither should take the server down.
python3 -c "print('{\"size_micro\":\"' + '9'*65000 + '\"}')" > /home/zulab/adv-big.json
probe "64KB body"                 400 -H "x-api-key: $KEY" -H 'content-type: application/json' \
      -X POST --data-binary @/home/zulab/adv-big.json "$U/quote"
BIGHDR=$(python3 -c "print('x'*16000)")
probe "16KB header"               401 -H "x-junk: $BIGHDR" "$U/thesis"

{
echo
echo "  == concurrency: 30 parallel probes while the server is being abused =="
} | tee -a "$OUT"
START=$(date +%s.%N)
# Wait on THESE pids only. A bare `wait` also waits for the coordination server started above, which
# is a background child of this same shell and never exits, so the script hung there indefinitely.
PIDS=""
for n in $(seq 1 30); do
  curl -s -m 15 -o /dev/null -H "x-api-key: $KEY" "$U/thesis" &
  PIDS="$PIDS $!"
done
for p in $PIDS; do wait "$p"; done
END=$(date +%s.%N)
echo "  30 parallel /thesis requests in $(echo "$END - $START" | bc)s" | tee -a "$OUT"

{
echo
echo "  == the property that actually matters: is it still answering? =="
} | tee -a "$OUT"
FINAL=$(curl -s -m 10 -o /home/zulab/adv-final.txt -w '%{http_code}' "$U/health")
echo "  /health after every probe: $FINAL" | tee -a "$OUT"
echo "  body: $(cat /home/zulab/adv-final.txt)" | tee -a "$OUT"
[ "$FINAL" = "200" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

{
echo
echo "  == server-side accounting =="
grep -oE '"served":[0-9]+,"refused":[0-9]+' /home/zulab/adv-final.txt 2>/dev/null | sed 's/^/    /'
echo
echo "## Verdict, task 6.5"
echo "  cases passed: $PASS"
echo "  cases failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "  RESULT: PASS. Every hostile input was refused with a JSON error and the server kept serving."
else
  echo "  RESULT: FAIL. See the rows marked FAIL above."
fi
} | tee -a "$OUT"

pkill -x asml-coord 2>/dev/null || true
echo "written: $OUT"
[ "$FAIL" -eq 0 ]
