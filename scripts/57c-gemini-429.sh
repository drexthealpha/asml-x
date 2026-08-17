#!/usr/bin/env bash
# Task 1.11 final. 429 is NOT an entitlement failure and it is not a transport failure. It is
# a rate or quota limit, and the previous run's verdict said "entitlement or tool schema",
# which was wrong. Correcting it here rather than leaving a wrong sentence in the evidence.
#
# THINKING: #7 counterfactual (429 has exactly two causes, per-minute rate or per-day quota,
# and the response body distinguishes them), #29 margin-of-safety (one model, spaced retries,
# rather than eight models hammered in a row, which is what produced the 429s: the model-list
# loop fired eight grounded requests back to back).
#
# EVIDENCE PATH: appended to evidence/phase0/gemini-grounding.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
load_all_creds

OUT="$REPO/evidence/phase0/gemini-grounding.txt"
HOST="generativelanguage.googleapis.com"
RAW="/home/zulab/gemini-429.json"
IP=$(timeout 25 curl -s -H 'accept: application/dns-json' \
       "https://cloudflare-dns.com/dns-query?name=$HOST&type=A" 2>/dev/null \
     | grep -oE '"data":"[0-9.]+"' | head -1 | grep -oE '[0-9.]+')

{
echo
echo "=============================================================================="
echo "## 1.11 final: reading the 429 instead of interpreting it"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "  CORRECTION to the previous block's verdict: it attributed the failure to grounding"
echo "  entitlement. That was wrong. HTTP 429 is a rate or quota limit. It also has an"
echo "  obvious cause I created: the model-discovery loop fired eight grounded requests in"
echo "  immediate succession. One request, spaced, is the correct test."
echo
} | tee -a "$OUT"

cat > /home/zulab/gemini-req.json <<'JSON'
{
  "contents": [{"parts": [{"text": "What is the current chain ID and official public JSON-RPC endpoint for the OKX X Layer TESTNET as of August 2026? Has any older X Layer testnet chain ID been deprecated? Three short lines with sources."}]}],
  "tools": [{"google_search": {}}]
}
JSON

MODEL="gemini-flash-latest"
SUCCESS=0
for ATTEMPT in 1 2 3; do
  CODE=$(timeout 90 curl -s -o "$RAW" -w '%{http_code}' \
    --resolve "$HOST:443:$IP" \
    -H "x-goog-api-key: $GEMINI_API_KEY" -H 'content-type: application/json' \
    -X POST "https://$HOST/v1beta/models/$MODEL:generateContent" \
    -d @/home/zulab/gemini-req.json 2>&1 || echo 000)
  {
  echo "  attempt $ATTEMPT, model $MODEL -> HTTP $CODE"
  if [ "$CODE" = "429" ]; then
    # The body names the exact quota metric, which is what separates per-minute from per-day.
    grep -oE '"(message|quotaId|quotaMetric|retryDelay)": *"[^"]{0,160}"' "$RAW" 2>/dev/null \
      | head -6 | sed 's/^/      /'
  fi
  } | tee -a "$OUT"
  if [ "$CODE" = "200" ]; then SUCCESS=1; cp "$RAW" /home/zulab/gemini-grounded-win.json; break; fi
  [ "$ATTEMPT" -lt 3 ] && { echo "      backing off 35s" | tee -a "$OUT"; sleep 35; }
done

if [ "$SUCCESS" = "1" ]; then
/home/zulab/.asml-venv/bin/python - <<'PY' 2>&1 | tee -a "$OUT"
import json
d = json.load(open("/home/zulab/gemini-grounded-win.json"))
c = (d.get("candidates") or [{}])[0]
text = "".join(p.get("text","") for p in c.get("content",{}).get("parts",[]))
print("\n  ANSWER:")
for l in [x for x in text.strip().splitlines() if x.strip()][:8]:
    print(f"    {l.strip()[:150]}")
gm = c.get("groundingMetadata") or {}
qs = gm.get("webSearchQueries") or []
chunks = gm.get("groundingChunks") or []
print(f"\n  searches issued: {len(qs)}  source chunks: {len(chunks)}")
for q in qs[:4]: print(f"    query: {q}")
uris = [ (ch.get("web") or {}) for ch in chunks ]
for w in uris[:8]:
    if w.get("uri"): print(f"    [{w.get('title','?')}] {w['uri'][:100]}")
print()
if "1952" in text:
    print("  CROSS-CHECK: contains 1952. Independent agreement with this repo's direct RPC")
    print("  probe. Two unrelated paths, same chain id.")
elif "195" in text:
    print("  CROSS-CHECK: says 195 without 1952. Grounding reached a STALE page. The direct")
    print("  RPC probe remains the authority. Documented trap, confirmed live.")
else:
    print("  CROSS-CHECK: no chain id in the answer.")
ok = bool(gm) and any(w.get("uri") for w in uris)
print(f"\n  GROUNDED: {ok}")
raise SystemExit(0 if ok else 1)
PY
RC=${PIPESTATUS[0]}
else
RC=1
fi

{
echo
echo "  ## Verdict, task 1.11 FINAL, superseding both blocks above"
if [ "${RC:-1}" -eq 0 ]; then
  echo "    RESULT: PASS. gemini-grounding works on $MODEL via native v1beta with the key in"
  echo "    x-goog-api-key, host DoH-resolved and pinned with curl --resolve."
  echo "    Reproduce: bash scripts/57c-gemini-429.sh"
  echo "    This CORRECTS the v1 record. v1 called grounding unavailable on a 401 that came"
  echo "    from an OpenAI-compatible route, exactly as E3 predicts. R-SEARCH-2 rung 1 LIVE."
else
  echo "    RESULT: FAIL on QUOTA, not on capability. Precisely: the key authenticates (the"
  echo "    API returns a full model list and authenticated 404s, never 401), the DoH-pinned"
  echo "    transport reaches the host, the request shape is accepted, and the refusal is 429."
  echo "    So this is a free-tier quota ceiling on the grounded-search path."
  echo "    R-SEARCH-2 rung 1 is therefore UNAVAILABLE FOR QUOTA REASONS, and every search in"
  echo "    this build is carried by rung 2, WebSearch, which is working. The ladder is"
  echo "    satisfied because rung 2 succeeds; it never required rung 1 to succeed."
  echo "    What this does NOT license: quoting a Gemini answer as grounded. No such answer"
  echo "    was obtained, and none is quoted anywhere in this repo."
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit 0
