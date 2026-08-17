#!/usr/bin/env bash
# Task 1.1 follow-up: verify halmos's ACTUAL Python requirement from the PyPI JSON API
# rather than trusting my own asserted floor of 3.11.
#
# THINKING: #49 skeptical (my floor claim is a claim until checked), #60 map-territory
# (halmos worked under Python 3.10 in v1, so the asserted floor contradicts observed
# reality and one of the two is wrong).
#
# api.github.com and some hosts are DNS-blocked here (E9), so resolve pypi.org over DoH
# and pin the IP.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/python-floor-verified.txt"
mkdir -p "$(dirname "$OUT")"

{
echo "halmos Python requirement, verified from the primary source"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

echo "Resolving pypi.org over DoH (E9: local resolver interferes with some hosts):"
IP=$(curl -sS --max-time 25 -H 'accept: application/dns-json' \
     "https://cloudflare-dns.com/dns-query?name=pypi.org&type=A" 2>/dev/null \
     | python3 -c "import json,sys; d=json.load(sys.stdin); print([a['data'] for a in d.get('Answer',[]) if a.get('type')==1][0])" 2>/dev/null)
echo "  pypi.org -> ${IP:-UNRESOLVED}"
echo

if [ -n "${IP:-}" ]; then
  curl -sS --max-time 40 --resolve "pypi.org:443:$IP" \
    "https://pypi.org/pypi/halmos/json" -o "$HOME/halmos-pypi.json" 2>/dev/null
else
  curl -sS --max-time 40 "https://pypi.org/pypi/halmos/json" -o "$HOME/halmos-pypi.json" 2>/dev/null
fi

if [ -s "$HOME/halmos-pypi.json" ]; then
  python3 - <<'PY'
import json, os
d = json.load(open(os.path.expanduser('~/halmos-pypi.json')))
info = d.get('info', {})
print("PRIMARY SOURCE: https://pypi.org/pypi/halmos/json")
print(f"  latest version   {info.get('version')}")
print(f"  requires_python  {info.get('requires_python')}")
print()
rels = d.get('releases', {})
if '0.3.3' in rels and rels['0.3.3']:
    rp = {f.get('requires_python') for f in rels['0.3.3']}
    print(f"  0.3.3 requires_python: {rp}")
else:
    print("  0.3.3 not in releases; available:", sorted(rels)[-6:])
PY
else
  echo "  FETCH FAILED. R-SEARCH-2 attempts: gemini-grounding (unavailable, see 1.11),"
  echo "  WebSearch (returned the page but not the metadata), DoH-pinned fetch (this),"
  echo "  browser render (pending). Do not assert a floor without this."
fi

echo
echo "Locally installed halmos, and the Python it actually runs on:"
command -v halmos >/dev/null 2>&1 && halmos --version 2>&1 | head -2 | sed 's/^/  /' || echo "  halmos not on PATH"
python3 --version 2>&1 | sed 's/^/  local python: /'
echo
echo "OBSERVED FACT from v1: halmos ran 14 theorems successfully under Python 3.10.12."
echo "That is evidence the 3.11 floor I asserted in 45-toolchain-floor.sh was WRONG."
} | tee "$OUT"

echo
echo "written: $OUT"
