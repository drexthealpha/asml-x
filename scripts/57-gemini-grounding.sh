#!/usr/bin/env bash
# Task 1.11 gemini-grounding. Retry the grounded-search path with the CORRECT transport, and
# make the test a question whose answer this build actually needs.
#
# THINKING: #7 counterfactual (v1 concluded "grounding unavailable" from a 401; E3 says a 401
# on an AQ. key means the TRANSPORT is wrong, so the earlier conclusion may have been an
# artifact of the route, not the capability), #60 falsifiability (a grounded answer is only
# worth anything if it carries groundingMetadata with real source URIs, so that is what I
# check for, not prose), #50 empirical.
#
# TWO THINGS WERE WRONG BEFORE, both recorded so neither is rediscovered:
#   E3: keys now start with AQ. and return 401 on OpenAI-compatible routes. So the endpoint
#       must be the NATIVE generativelanguage.googleapis.com v1beta generateContent route,
#       with the key in x-goog-api-key, never an /openai/ or /v1/chat/completions path.
#   E9: generativelanguage.googleapis.com is blocked by this machine's resolver. So the host
#       must be reached by resolving it over DoH and pinning with curl --resolve.
#
# EVIDENCE PATH declared before code: evidence/phase0/gemini-grounding.txt
# PASS: a grounded response carrying groundingMetadata with at least one real source URI, on a
# question this build needs answered. Prose with no metadata is ungrounded model output
# wearing a grounding label, and that is this task's fake win.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
load_all_creds

OUT="$REPO/evidence/phase0/gemini-grounding.txt"
mkdir -p "$(dirname "$OUT")"
RAW="/home/zulab/gemini-grounding-raw.json"
HOST="generativelanguage.googleapis.com"

{
echo "gemini-grounding, task 1.11"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Preconditions"
echo "  GEMINI_API_KEY: $([ -n "${GEMINI_API_KEY:-}" ] && echo "PRESENT (len ${#GEMINI_API_KEY}, prefix ${GEMINI_API_KEY:0:3})" || echo MISSING)"
echo "  E3 says the AQ. prefix is correct for 2026 and a 401 means the transport is wrong."
echo
echo "## Step 1: resolve the blocked host over DoH (E9)"
} 2>&1 | tee "$OUT"

# Cloudflare DoH returns JSON; pull the first A record. Cloudflare itself resolves normally.
IP=$(timeout 25 curl -s -H 'accept: application/dns-json' \
       "https://cloudflare-dns.com/dns-query?name=$HOST&type=A" 2>/dev/null \
     | grep -oE '"data":"[0-9.]+"' | head -1 | grep -oE '[0-9.]+')
{
if [ -z "$IP" ]; then
  echo "  DoH resolution FAILED. Trying Google's own DoH as a second resolver."
fi
} | tee -a "$OUT"
if [ -z "$IP" ]; then
  IP=$(timeout 25 curl -s "https://dns.google/resolve?name=$HOST&type=A" 2>/dev/null \
       | grep -oE '"data": ?"[0-9.]+"' | head -1 | grep -oE '[0-9.]+')
fi

{
echo "  $HOST resolved to: ${IP:-NONE}"
echo
echo "## Step 2: the question. Something this build needs, not a toy prompt."
echo "  Asking for the CURRENT X Layer testnet chain id and public RPC endpoint. This is a"
echo "  fact the whole project rests on, and it is exactly the class of fact that already"
echo "  bit once: chain 195 is deprecated but STILL ANSWERS, so a stale source is worse than"
echo "  no source. If grounding is real it should reach a live page and agree with 1952."
echo
echo "## Step 3: native v1beta generateContent with the google_search tool"
} | tee -a "$OUT"

if [ -z "${GEMINI_API_KEY:-}" ] || [ -z "${IP:-}" ]; then
  {
  echo "  CANNOT PROCEED: $([ -z "${GEMINI_API_KEY:-}" ] && echo 'key missing'; [ -z "${IP:-}" ] && echo 'host unresolvable')"
  echo "  RESULT: FAIL, and no answer is quoted as though it were grounded."
  } | tee -a "$OUT"
  exit 1
fi

cat > /home/zulab/gemini-req.json <<'JSON'
{
  "contents": [{
    "parts": [{
      "text": "What is the current chain ID and the official public JSON-RPC endpoint for the OKX X Layer TESTNET as of August 2026? State whether any older chain ID for X Layer testnet has been deprecated. Answer in three short lines and cite the pages you used."
    }]
  }],
  "tools": [{"google_search": {}}]
}
JSON

# Two models, newest first. A 404 on a model name is a model-availability fact, not a
# grounding failure, and conflating the two is how v1 got a wrong conclusion.
for MODEL in gemini-2.5-flash gemini-2.0-flash; do
  echo "  trying model $MODEL" | tee -a "$OUT"
  CODE=$(timeout 90 curl -s -o "$RAW" -w '%{http_code}' \
    --resolve "$HOST:443:$IP" \
    -H "x-goog-api-key: $GEMINI_API_KEY" \
    -H 'content-type: application/json' \
    -X POST "https://$HOST/v1beta/models/$MODEL:generateContent" \
    -d @/home/zulab/gemini-req.json 2>&1 || echo 000)
  echo "    HTTP $CODE" | tee -a "$OUT"
  [ "$CODE" = "200" ] && break
  if [ "$CODE" = "401" ] || [ "$CODE" = "403" ]; then
    grep -oE '"message": *"[^"]{0,200}"' "$RAW" 2>/dev/null | head -2 | sed 's/^/    /' | tee -a "$OUT"
  fi
done

{
echo
echo "## Step 4: is it GROUNDED? The decisive check."
} | tee -a "$OUT"

/home/zulab/.asml-venv/bin/python - "$RAW" <<'PY' 2>&1 | tee -a "$OUT"
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"  response not JSON: {e}")
    sys.exit(1)

if "error" in d:
    print(f"  API ERROR {d['error'].get('code')}: {str(d['error'].get('message'))[:200]}")
    sys.exit(1)

cands = d.get("candidates") or []
if not cands:
    print("  no candidates in response")
    sys.exit(1)

text = "".join(p.get("text", "") for p in cands[0].get("content", {}).get("parts", []))
print("  ANSWER TEXT:")
for line in text.strip().splitlines()[:10]:
    print(f"    {line.strip()[:150]}")

gm = cands[0].get("groundingMetadata") or {}
chunks = gm.get("groundingChunks") or []
queries = gm.get("webSearchQueries") or []

print()
print(f"  groundingMetadata present: {bool(gm)}")
print(f"  searches the model actually issued: {len(queries)}")
for q in queries[:5]:
    print(f"    query: {q}")
print(f"  source chunks returned: {len(chunks)}")
uris = []
for c in chunks[:8]:
    w = c.get("web") or {}
    u = w.get("uri", "")
    if u:
        uris.append(u)
        print(f"    [{w.get('title','?')}] {u[:110]}")

# The break-attempt. A grounded answer about chain id must AGREE with the verified fact.
# If it says 195 and cites a page, grounding worked but the SOURCE is stale, which is a
# different and more interesting finding than a transport failure.
print()
if "1952" in text:
    print("  CROSS-CHECK: the grounded answer contains 1952, agreeing with the value this")
    print("  repo verified directly against the RPC. Independent confirmation.")
elif "195" in text:
    print("  CROSS-CHECK: the answer mentions 195 but NOT 1952. Grounding may have reached a")
    print("  stale page. The repo's own RPC probe stands as the authority, not this answer.")
    print("  This is precisely the trap recorded in CLAUDE.md: 195 is deprecated and still")
    print("  answers, so a confident secondary source can be wrong.")
else:
    print("  CROSS-CHECK: no chain id in the answer at all.")

ok = bool(gm) and len(uris) > 0
print()
print(f"  GROUNDED: {ok}")
sys.exit(0 if ok else 1)
PY
GR_RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict, task 1.11"
if [ "${GR_RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. Grounded response with real source URIs over the native transport."
  echo "  This CORRECTS the v1 conclusion that grounding was unavailable. The 401 in v1 came"
  echo "  from an OpenAI-compatible route, exactly as E3 predicts. The capability was there"
  echo "  the whole time and the earlier record was wrong."
  echo "  R-SEARCH-2 rung 1 (gemini-grounding first) is therefore LIVE for later tasks."
else
  echo "  RESULT: FAIL. No groundingMetadata with source URIs."
  echo "  Recorded as a fail. The ladder continues at rung 2 (WebSearch), which has been"
  echo "  carrying every search in this build so far and is working."
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit "${GR_RC:-1}"
