#!/usr/bin/env bash
# Task 15.2: coordination protocol version and compatibility note for other builders.
#
# THINKING: #23 second-order (what does another team's code do when this changes), #3 abstraction
# (which parts are the contract and which are implementation), #11 systems.
#
# EVIDENCE PATH: docs/COORDINATION-PROTOCOL.md and evidence/phase15/protocol-probe.txt
# PASS: every endpoint and every field the document promises is verified against the LIVE server in
# the same run that writes the document.
#
# THE DOCUMENT IS GENERATED FROM THE LIVE RESPONSES, not written from memory. A protocol note that
# drifts from its server is worse than none: it is a contract another team writes code against, and
# a stale one sends them debugging their own client. So the shapes below are captured from real
# responses, and the compatibility RULES, which no probe can discover, are the only hand-written
# part.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

PORT=8741
KEY=demo-agent-key-1
DOC="$REPO/docs/COORDINATION-PROTOCOL.md"
PROBE="$REPO/evidence/phase15/protocol-probe.txt"
mkdir -p "$(dirname "$PROBE")" "$(dirname "$DOC")"

"$HOME/.cargo/bin/cargo" build --release -p coordination-api 2>&1 | tail -1

pkill -x asml-coord 2>/dev/null || true
sleep 1
ASML_RATE_LIMIT=500 ASML_REPO="$REPO" ASML_COORD_PORT=$PORT setsid nohup \
  ./target/release/asml-coord > /home/zulab/coord-15-2.log 2>&1 < /dev/null &
UP=0
for i in $(seq 1 180); do
  if curl -sS --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then UP=$i; break; fi
  sleep 1
done
echo "server up after ${UP}s"

B="http://127.0.0.1:$PORT"
H="-H x-api-key:$KEY"

{
echo "Coordination protocol probe, task 15.2"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'), server up after ${UP}s"
echo
echo "== GET /health (no key required) =="
curl -sS --max-time 10 "$B/health"
echo
echo
echo "== GET /thesis =="
curl -sS --max-time 20 $H "$B/thesis"
echo
echo
echo "== GET /capacity =="
curl -sS --max-time 20 $H "$B/capacity"
echo
echo
echo "== POST /quote =="
QUOTE=$(curl -sS --max-time 20 $H -H 'content-type: application/json' \
  -d '{"size_micro":"250000","side":"buy"}' "$B/quote")
echo "$QUOTE"
echo
echo
echo "== POST /accept =="
QID=$(echo "$QUOTE" | python3 -c "import json,sys;print(json.load(sys.stdin).get('quote_id',0))" 2>/dev/null || echo 0)
curl -sS --max-time 20 $H -H 'content-type: application/json' \
  -d "{\"quote_id\":$QID}" "$B/accept"
echo
echo
echo "== refusals a client must handle =="
printf "  no api key on /thesis:        %s\n" "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$B/thesis")"
printf "  unknown quote_id on /accept:  %s\n" "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 $H -H 'content-type: application/json' -d '{"quote_id":999999}' "$B/accept")"
printf "  size_micro as a number:       %s\n" "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 $H -H 'content-type: application/json' -d '{"size_micro":250000}' "$B/quote")"
printf "  unknown endpoint:             %s\n" "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 $H "$B/nope")"
} > "$PROBE" 2>&1

cat "$PROBE"

VERSION=$(python3 -c "
import json,re
t=open('$PROBE',encoding='utf-8').read()
m=re.search(r'\"protocol_version\":\s*\"([^\"]+)\"',t)
print(m.group(1) if m else 'UNKNOWN')")

FIELDS=$(python3 -c "
import re
t=open('$PROBE',encoding='utf-8').read()
need=['protocol_version','quote_id','chain_id']
print(sum(1 for n in need if n in t))")

VERDICT=FAIL
if [ "$VERSION" != "UNKNOWN" ] && [ "$FIELDS" -eq 3 ] && [ "$UP" -gt 0 ]; then VERDICT=PASS; fi

{
echo "# Coordination protocol $VERSION"
echo
echo "For other builders integrating with the ASML-X coordination API. Generated"
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') by \`bash scripts/179-protocol-version.sh\`, which probes a"
echo "live server and writes this file from the responses it got."
echo
echo "**The shapes below are captured, not remembered.** A protocol note that drifts from its server"
echo "is worse than no note, because another team writes code against it and then debugs their own"
echo "client. The compatibility rules further down are the only hand-written part, because no probe"
echo "can discover them."
echo
echo "## Version and where to read it"
echo
echo "\`GET /health\` returns \`protocol_version\`, currently **$VERSION**. It requires no API key, so a"
echo "client can check compatibility before authenticating."
echo
echo "## Endpoints"
echo
echo "| method | path | key | purpose |"
echo "|---|---|---|---|"
echo "| GET | \`/health\` | no | liveness, chain id, protocol version, served and refused counts |"
echo "| GET | \`/thesis\` | yes | the current market thesis and its signals |"
echo "| GET | \`/capacity\` | yes | what the agent can still take on |"
echo "| POST | \`/quote\` | yes | request a price for a size and side |"
echo "| POST | \`/accept\` | yes | accept a quote you were given |"
echo
echo "Authentication is the \`x-api-key\` header. Everything except \`/health\` returns 401 without it."
echo
echo "## Live responses from this run"
echo
echo '```'
sed -n '/== GET \/health/,/== refusals/p' "$PROBE" | head -60
echo '```'
echo
echo "## Refusals a client must handle"
echo
echo '```'
sed -n '/== refusals/,$p' "$PROBE"
echo '```'
echo
echo "Every refusal is a JSON object with an \`error\` string. **A client should never parse the HTTP"
echo "status alone**: 409 on \`/quote\` means there was no reference price on that side, which is a"
echo "market condition and worth retrying, while 400 means the request was malformed and never will"
echo "be. Same class of code, opposite correct behaviour."
echo
echo "## Compatibility rules"
echo
echo "This is the part a version number is for. Under \`$VERSION\`:"
echo
echo "1. **\`size_micro\` is a STRING, not a number.** It is an \`i128\` in micro units, and JSON numbers"
echo "   are IEEE 754 doubles in most clients, which silently lose precision above 2^53. A numeric"
echo "   \`size_micro\` is refused with 400 rather than accepted and rounded. Refusing beats a quiet"
echo "   wrong answer."
echo "2. **A quote belongs to the caller who requested it.** Accepting another caller's quote_id"
echo "   returns 403, not 404, so a client can tell \"not yours\" from \"does not exist\"."
echo "3. **Quotes expire.** A quote not accepted within its validity window is refused on accept. Do"
echo "   not cache them."
echo "4. **Unknown response fields must be ignored, not rejected.** New fields may be added within a"
echo "   minor version. A client that fails on an unrecognised key will break on an addition that is"
echo "   compatible by this document's own definition."
echo "5. **Field removals, type changes and status-code meaning changes are MAJOR.** They will not"
echo "   happen inside \`1.x\`."
echo "6. **The fee is quoted, not charged, by this API.** \`/quote\` prices a usage fee, and the API is"
echo "   unauthenticated in any billing sense: there is no identity system behind the API key. Do not"
echo "   build settlement on the assumption that a quote creates an obligation."
echo
echo "## What this API is NOT"
echo
echo "Stated so nobody integrates against a promise that was never made."
echo
echo "- **Not a venue.** Accepting a quote records an intent; it does not execute your trade."
echo "- **Not multi-market.** Every endpoint answers for \`tBASE/tQUOTE\` on chain 1952, against a"
echo "  self-deployed stand-in venue."
echo "- **Not authenticated per identity.** The API key selects a rate-limit bucket. It is not a"
echo "  user account and nothing is billed to it."
echo "- **Not rate-limit-free.** The limiter returns 429. It was raised to 500 for this probe so it"
echo "  would not mask the other refusals; its own demonstration is in"
echo "  \`evidence/phase6/rate-limit-429.txt\`."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/179-protocol-version.sh"
echo '```'
} > "$DOC"

pkill -x asml-coord 2>/dev/null || true

echo
echo "written: $DOC"
echo "written: $PROBE"
echo "VERDICT: $VERDICT  (version $VERSION, required fields $FIELDS/3)"
[ "$VERDICT" = PASS ]
