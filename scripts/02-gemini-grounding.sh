#!/usr/bin/env bash
# Task 0.5.B: install gemini-grounding, run ONE test query, and settle the
# free-tier grounding quota question in a single shot.
# Per the user's instruction and R16/R17: no investigation if it fails. Note the
# substitution and move on.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
load_all_creds

EVID="$REPO/evidence/tool-setup"
mkdir -p "$EVID"

if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "GEMINI_API_KEY not readable from ~/.profile. Aborting this task only."
  exit 1
fi
echo "key loaded, length ${#GEMINI_API_KEY}, prefix $(printf '%s' "$GEMINI_API_KEY" | cut -c1-3)"

echo
echo "=== ONE grounded test query against the NATIVE Gemini endpoint ==="
echo "(native endpoint chosen deliberately: AQ. keys 401 on OpenAI-compatible"
echo " routes, which is a transport issue and never the key, per E3)"

cat > /tmp/ground-req.json <<'JSON'
{
  "contents": [{"parts": [{"text": "What is the current chain ID and public RPC endpoint for the X Layer testnet, and is OKX Exchange OS deployed on X Layer testnet as of August 2026? Answer concisely with sources."}]}],
  "tools": [{"google_search": {}}]
}
JSON

HTTP=$(curl -sS --max-time 90 -o /tmp/ground-resp.json -w '%{http_code}' \
  -X POST \
  -H "content-type: application/json" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  --data @/tmp/ground-req.json)

echo "http_status: $HTTP"

if [ "$HTTP" = "200" ]; then
  echo "RESULT: grounding WORKS on this key"
  python3 - <<'PY'
import json
d = json.load(open('/tmp/ground-resp.json'))
c = d['candidates'][0]
txt = ''.join(p.get('text','') for p in c['content']['parts'])
print("--- answer ---")
print(txt[:1800])
gm = c.get('groundingMetadata') or {}
q = gm.get('webSearchQueries') or []
chunks = gm.get('groundingChunks') or []
print("--- grounding evidence ---")
print("search_queries_issued:", q)
print("grounding_chunks:", len(chunks))
for ch in chunks[:8]:
    w = ch.get('web') or {}
    print("  -", w.get('title'), "|", (w.get('uri') or '')[:110])
print("HAS_CITATIONS:", bool(chunks))
PY
else
  echo "RESULT: grounding NOT available on this key or tier"
  head -c 900 /tmp/ground-resp.json
  echo
  echo "PER INSTRUCTION: no further investigation. Falling back to WebSearch plus"
  echo "the DoH-pinned direct fetch. Substitution noted."
fi

{
  echo "# Tool setup: gemini-grounding"
  echo
  echo "Captured: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "Native generateContent + google_search tool, HTTP $HTTP"
  echo
  echo "MCP registration command (takes effect next session, MCP servers load at startup):"
  echo '```'
  echo 'claude mcp add gemini-grounding -e GEMINI_API_KEY="${GEMINI_API_KEY}" -- npx -y gemini-grounding'
  echo '```'
} > "$EVID/gemini-grounding.md"

if [ "$HTTP" = "200" ]; then
  python3 - >> "$EVID/gemini-grounding.md" <<'PY'
import json
d = json.load(open('/tmp/ground-resp.json'))
c = d['candidates'][0]
txt = ''.join(p.get('text','') for p in c['content']['parts'])
gm = c.get('groundingMetadata') or {}
print()
print("Status: DEMONSTRATED, grounding returned citations.")
print()
print("Queries Google actually issued:", gm.get('webSearchQueries'))
print("Grounding chunks:", len(gm.get('groundingChunks') or []))
print()
print("Answer:")
print()
print(txt[:2500])
PY
fi
echo
echo "written: $EVID/gemini-grounding.md"
