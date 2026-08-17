#!/usr/bin/env bash
# Task 1.11 continued. The transport is FIXED and the key is FINE: the 404 body is a real,
# authenticated API error ("This model models/gemini-2.0-flash is no longer available"), not a
# 401. So the only remaining unknown is the model name, and I am not going to guess it.
#
# THINKING: #50 empirical (the API can enumerate its own models, which beats any blog post),
# #22 inversion (instead of guessing names until one works, ask what exists).
#
# EVIDENCE PATH: appended to evidence/phase0/gemini-grounding.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
load_all_creds

OUT="$REPO/evidence/phase0/gemini-grounding.txt"
HOST="generativelanguage.googleapis.com"
IP=$(timeout 25 curl -s -H 'accept: application/dns-json' \
       "https://cloudflare-dns.com/dns-query?name=$HOST&type=A" 2>/dev/null \
     | grep -oE '"data":"[0-9.]+"' | head -1 | grep -oE '[0-9.]+')

{
echo
echo "=============================================================================="
echo "## 1.11 continued: enumerate models instead of guessing names"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "  KEY FINDING from the previous run, and it corrects the record: the response was a"
echo "  404 with an authenticated error body naming the retired model, NOT a 401. The key"
echo "  works and the native transport works. E3 was right and the v1 conclusion that"
echo "  grounding is unavailable was an artifact of the OpenAI-compatible route."
echo
} | tee -a "$OUT"

timeout 60 curl -s --resolve "$HOST:443:$IP" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  "https://$HOST/v1beta/models?pageSize=200" > /home/zulab/gemini-models.json 2>&1

/home/zulab/.asml-venv/bin/python - <<'PY' 2>&1 | tee -a "$OUT"
import json
d = json.load(open("/home/zulab/gemini-models.json"))
if "error" in d:
    print(f"  LIST FAILED {d['error'].get('code')}: {str(d['error'].get('message'))[:180]}")
    raise SystemExit(1)
ms = d.get("models", [])
print(f"  models the key can see: {len(ms)}")
gen = [m for m in ms if "generateContent" in (m.get("supportedGenerationMethods") or [])]
print(f"  supporting generateContent: {len(gen)}")
print("  candidates for grounded search, newest-looking first:")
names = sorted((m["name"].split("/")[-1] for m in gen), reverse=True)
for n in names[:25]:
    print(f"    {n}")
open("/home/zulab/gemini-model-names.txt", "w").write("\n".join(names))
PY

# Try each real model in turn with the google_search tool. First one that returns
# groundingMetadata with source URIs wins.
cat > /home/zulab/gemini-req.json <<'JSON'
{
  "contents": [{"parts": [{"text": "What is the current chain ID and the official public JSON-RPC endpoint for the OKX X Layer TESTNET as of August 2026? State whether any older X Layer testnet chain ID has been deprecated. Three short lines, cite your sources."}]}],
  "tools": [{"google_search": {}}]
}
JSON

RAW="/home/zulab/gemini-grounding-raw.json"
WINNER=""
{
echo
echo "  ## Trying real model names with the google_search tool"
} | tee -a "$OUT"

# Prefer flash tiers: cheaper, and grounding support is what is being tested, not reasoning.
CANDIDATES=$(grep -E 'flash|pro' /home/zulab/gemini-model-names.txt 2>/dev/null \
             | grep -vE 'embedding|image|tts|vision|live|native-audio|thinking-exp' \
             | head -8)
for MODEL in $CANDIDATES; do
  CODE=$(timeout 90 curl -s -o "$RAW" -w '%{http_code}' \
    --resolve "$HOST:443:$IP" \
    -H "x-goog-api-key: $GEMINI_API_KEY" -H 'content-type: application/json' \
    -X POST "https://$HOST/v1beta/models/$MODEL:generateContent" \
    -d @/home/zulab/gemini-req.json 2>&1 || echo 000)
  HASGM=$(grep -c groundingMetadata "$RAW" 2>/dev/null || echo 0)
  echo "    $MODEL -> HTTP $CODE, groundingMetadata blocks: $HASGM" | tee -a "$OUT"
  if [ "$CODE" = "200" ] && [ "${HASGM:-0}" -gt 0 ]; then
    WINNER="$MODEL"; cp "$RAW" /home/zulab/gemini-grounded-win.json; break
  fi
  # Keep the first HTTP 200 even without grounding, so an ungrounded-but-working model is
  # distinguishable from a broken one.
  [ "$CODE" = "200" ] && [ -z "$WINNER" ] && cp "$RAW" /home/zulab/gemini-200-nogm.json
done

{
echo
echo "  ## Grounding check on the winning response"
} | tee -a "$OUT"

WIN="$WINNER" /home/zulab/.asml-venv/bin/python - <<'PY' 2>&1 | tee -a "$OUT"
import json, os, sys
win = os.environ.get("WIN") or ""
path = "/home/zulab/gemini-grounded-win.json" if win else "/home/zulab/gemini-200-nogm.json"
if not os.path.exists(path):
    print("  no HTTP 200 response from any model. Grounding unavailable via this key.")
    sys.exit(1)
d = json.load(open(path))
c = (d.get("candidates") or [{}])[0]
text = "".join(p.get("text","") for p in c.get("content",{}).get("parts",[]))
print(f"  model: {win or 'none grounded'}")
print("  ANSWER:")
for l in [x for x in text.strip().splitlines() if x.strip()][:8]:
    print(f"    {l.strip()[:150]}")
gm = c.get("groundingMetadata") or {}
qs = gm.get("webSearchQueries") or []
chunks = gm.get("groundingChunks") or []
print()
print(f"  searches issued: {len(qs)}  source chunks: {len(chunks)}")
for q in qs[:4]: print(f"    query: {q}")
uris = []
for ch in chunks[:8]:
    w = ch.get("web") or {}
    if w.get("uri"):
        uris.append(w["uri"]); print(f"    [{w.get('title','?')}] {w['uri'][:100]}")
print()
if "1952" in text:
    print("  CROSS-CHECK: answer contains 1952, independently agreeing with this repo's own")
    print("  direct RPC probe. Two independent paths to the same chain id.")
elif "195" in text:
    print("  CROSS-CHECK: answer says 195 without 1952. Grounding reached a STALE page. The")
    print("  repo's direct RPC probe remains the authority. This is the documented trap.")
else:
    print("  CROSS-CHECK: no chain id in the answer.")
ok = bool(gm) and bool(uris)
print()
print(f"  GROUNDED: {ok}")
sys.exit(0 if ok else 1)
PY
RC=${PIPESTATUS[0]}

{
echo
echo "  ## Verdict, task 1.11 final"
if [ "${RC:-1}" -eq 0 ]; then
  echo "    RESULT: PASS. gemini-grounding WORKS via the native v1beta transport."
  echo "    Working model: $WINNER"
  echo "    Reproduce: bash scripts/57b-gemini-models.sh"
  echo "    R-SEARCH-2 rung 1 is LIVE. Corrects the v1 record, which called this unavailable"
  echo "    on the strength of a 401 that came from the wrong route."
else
  echo "    RESULT: FAIL, and the failure is now precisely located rather than vague."
  echo "    The key authenticates (the API returns authenticated 404s and a model list, not"
  echo "    401s), the DoH-pinned transport reaches the host, but no available model returned"
  echo "    groundingMetadata. So the missing piece is grounding ENTITLEMENT or the tool"
  echo "    schema on the models this key can see, NOT the key and NOT the network."
  echo "    R-SEARCH-2 continues at rung 2, WebSearch, which has carried every search here."
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit "${RC:-1}"
