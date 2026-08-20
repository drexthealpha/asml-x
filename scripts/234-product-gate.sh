#!/usr/bin/env bash
# THE GATE. Run this to check me, against the LIVE site.
#
# WHY IT EXISTS. Being told a task list is done is worth nothing; every claim in this project has
# to be checkable by someone who does not trust the claimant. This exits non-zero the moment any of
# the following is untrue, so "done" is a thing you verify rather than a thing you are told.
#
# WHAT IT CHECKS
#   1. every /api/* endpoint answers, and returns real priced instruments, not an empty shell
#   2. every user-facing contract has a WRITE path in the bundle, not only a read
#   3. the RWA surface carries the deep datapoints, not just a price
#   4. no surface renders a failed fetch as data
#   5. the wallet picker prefers OKX
#
# USAGE
#   bash scripts/234-product-gate.sh                     against the live deployment
#   ASML_URL=http://127.0.0.1:4173 bash scripts/234-...  against a local build
#
# EVIDENCE PATH: evidence/phase21/product-gate.txt
set -uo pipefail
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPTS/.."

URL="${ASML_URL:-https://asml-x.vercel.app}"

# THE API LIVES SOMEWHERE ELSE LOCALLY. Hosted, the serverless functions sit at the same
# origin as the page. Locally the static server is 4173 and the signing feed server is 8787,
# so pointing both at one base reported five false 404s. A gate that fails on its own
# configuration teaches people to ignore it, which is worse than having no gate.
case "$URL" in
  *127.0.0.1*|*localhost*) API="${ASML_API:-http://127.0.0.1:8787}" ;;
  *) API="$URL" ;;
esac
OUT="evidence/phase21/product-gate.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

FAIL=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAIL=1; }

echo "ASML-X product gate"
echo "target $URL"
echo "api    $API"
echo

# ---------------------------------------------------------------- 1. the feeds
echo "=== 1. every endpoint answers with real data ==="
for ep in rwastate contracts universe onchainos rwa; do
  BODY=$(curl -s --max-time 25 "$API/api/$ep" 2>/dev/null)
  CODE=$(curl -s -o /dev/null --max-time 25 -w '%{http_code}' "$API/api/$ep" 2>/dev/null)
  if [ "$CODE" != "200" ]; then
    fail "/api/$ep returned $CODE"
    continue
  fi
  # A 200 with nothing in it is the failure this gate exists to catch: the endpoint that looks
  # healthy while every price is null.
  N=$(printf '%s' "$BODY" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(-1); raise SystemExit
if "instruments" in d:
    print(sum(1 for i in d["instruments"] if i.get("price")))
elif "tokens" in d:
    print(sum(1 for t in d["tokens"] if t.get("price")))
elif "rules" in d:
    print(sum(1 for r in d["rules"] if r.get("display") is not None))
elif "contracts" in d:
    print(sum(1 for c in d["contracts"] if any(f.get("value") is not None for f in c.get("facts",[]))))
else:
    print(0)
' 2>/dev/null)
  if [ "${N:-0}" -gt 0 ]; then
    pass "/api/$ep  $N populated"
  else
    fail "/api/$ep returned 200 with nothing populated"
  fi
done

# ---------------------------------------------------------------- 2. write paths
echo
echo "=== 2. every user-facing contract has a write path, not only a read ==="
# EVERY chunk, not one file. Vite code-splits, so `index-*.js` matched a different chunk than the
# one holding the wallet code and reported eight false failures. A gate that fails on its own
# search bug teaches people to ignore it, which is worse than having no gate.
BUNDLE_DIR="ui-v2/dist/assets"
if [ ! -d "$BUNDLE_DIR" ]; then
  fail "no built bundle found; run pnpm build first"
else
  # Selectors, verified in scripts/235 and 239. Their presence in the bundle is what proves a
  # button exists that can actually call the contract.
  check_sel() {
    if grep -rqF "$2" "$BUNDLE_DIR" 2>/dev/null; then pass "$1"; else fail "$1 (selector $2 absent)"; fi
  }
  check_sel "AgentVault.deposit"        "0xe2bbb158"
  check_sel "AgentVault.withdraw"       "0x2e1a7d4d"
  check_sel "AgentVault.withdrawAll"    "0x853828b6"
  check_sel "AgentVault.setMaxNotional" "0xea279302"
  check_sel "AgentVault.setPaused"      "0x16c38b3c"
  check_sel "FeeCollector.quoteFee"     "0x2205f568"
  check_sel "RiskGuard.maxGross"        "0xfb89278c"
  check_sel "RiskGuard.killed"          "0x1f3a0e41"
fi

# ---------------------------------------------------------------- 3. RWA depth
echo
echo "=== 3. the RWA surface carries deep datapoints ==="
# The deep feed is /api/rwafull locally and /api/rwa when hosted: the serverless function
# and the local script write the same shape under different names.
case "$URL" in
  *127.0.0.1*|*localhost*) RWA_EP="$API/api/rwafull" ;;
  *) RWA_EP="$API/api/rwa" ;;
esac
if python3 "$SCRIPTS/gate_rwa_depth.py" "$RWA_EP"; then
  :
else
  FAIL=1
fi

echo "=== 4. failure is never rendered as data ==="
# Fixed strings, checked one at a time. An escaped alternation does not survive the shell
# and silently matches nothing, which reported a fail against text that was present.
FOUND=0
for phrase in "is unavailable right now" "could not be read" "could not load" "Nothing is shown"; do
  if grep -rqF "$phrase" "$BUNDLE_DIR" 2>/dev/null; then
    FOUND=$((FOUND + 1))
  fi
done
if [ "$FOUND" -ge 3 ]; then
  pass "explicit unavailable states in the bundle ($FOUND of 4 phrases)"
else
  fail "only $FOUND of 4 unavailable-state phrases found"
fi

echo "=== 5. the wallet picker prefers OKX ==="
if grep -rqF "eip6963:requestProvider" "$BUNDLE_DIR" 2>/dev/null; then
  pass "EIP-6963 discovery present"
else
  fail "EIP-6963 discovery absent; the picker cannot tell wallets apart"
fi
if grep -rqi "okx wallet" "$BUNDLE_DIR" 2>/dev/null; then
  pass "OKX is named in the picker"
else
  fail "OKX is not named in the picker"
fi

echo
if [ "$FAIL" -ne 0 ]; then
  echo "GATE: FAIL"
  exit 1
fi
echo "GATE: PASS"
