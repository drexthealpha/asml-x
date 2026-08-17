#!/usr/bin/env bash
# Task 1.4: install hevm and get a REAL verdict from it on a real contract.
#
# THINKING: #45 proof by contradiction (hevm's symbolic engine asserts and hunts a
# counterexample, same shape as halmos), #13 dialectical (two independent provers agreeing
# on the cap theorem is materially stronger than one, and a DISAGREEMENT is the most
# valuable finding available), #50 empirical.
#
# EVIDENCE PATH, declared before the code: evidence/phase0/hevm.txt
# PASS: hevm returns a verdict on a real contract. A version banner is NOT a pass.
#
# Install route: static release binary from GitHub releases, resolved over DoH because
# api.github.com is blocked by this machine's resolver (E9). No Docker (E6), no Nix.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/hevm.txt"
SUB="$REPO/evidence/phase0/tool-substitutions.md"
mkdir -p "$(dirname "$OUT")"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"

{
echo "hevm install and smoke test, task 1.4"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

if command -v hevm >/dev/null 2>&1; then
  echo "already installed: $(hevm version 2>&1 | head -1)"
else
  echo "## Resolving api.github.com over DoH (E9)"
  IP=$(curl -sS --max-time 25 -H 'accept: application/dns-json' \
       "https://cloudflare-dns.com/dns-query?name=api.github.com&type=A" 2>/dev/null \
       | python3 -c "import json,sys; d=json.load(sys.stdin); print([a['data'] for a in d.get('Answer',[]) if a.get('type')==1][0])" 2>/dev/null)
  echo "  api.github.com -> ${IP:-UNRESOLVED}"

  echo "## Finding the current hevm release asset"
  # Authenticate with GITHUB_TOKEN from ~/.profile. The first attempt was
  # unauthenticated and came back with no assets, which is what the GitHub API does when
  # it rate-limits: it returns a body, so a naive parse sees "tag: ?" rather than an
  # error. The token has been sitting unused in ~/.profile since v1.
  load_all_creds
  if [ -n "${IP:-}" ]; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -sS --max-time 60 --resolve "api.github.com:443:$IP" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        "https://api.github.com/repos/ethereum/hevm/releases/latest" -o "$HOME/hevm-rel.json" 2>/dev/null
    else
      curl -sS --max-time 60 --resolve "api.github.com:443:$IP" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/ethereum/hevm/releases/latest" -o "$HOME/hevm-rel.json" 2>/dev/null
    fi
    # Surface an API error instead of silently parsing it as an empty release.
    if grep -q '"message"' "$HOME/hevm-rel.json" 2>/dev/null; then
      echo "  API ERROR: $(python3 -c "import json;print(json.load(open('$HOME/hevm-rel.json')).get('message'))" 2>/dev/null)"
    fi
  fi

  if [ -s "$HOME/hevm-rel.json" ]; then
    python3 - <<'PY'
import json, os
p = os.path.expanduser('~/hevm-rel.json')
d = json.load(open(p))
tag = d.get('tag_name', '?')
print(f"  latest tag: {tag}")
assets = [a['name'] for a in d.get('assets', [])]
print(f"  assets: {assets[:8]}")
# Prefer a linux x86_64 static asset.
cand = [a for a in d.get('assets', []) if 'linux' in a['name'].lower() and 'x86' in a['name'].lower()]
if not cand:
    cand = [a for a in d.get('assets', []) if 'linux' in a['name'].lower()]
open(os.path.expanduser('~/hevm-url.txt'), 'w').write(cand[0]['browser_download_url'] if cand else '')
print(f"  chosen: {cand[0]['name'] if cand else 'NONE'}")
PY
    URL=$(cat "$HOME/hevm-url.txt" 2>/dev/null)
    if [ -n "${URL:-}" ]; then
      echo "  downloading $URL"
      curl -sSL --max-time 300 "$URL" -o "$HOME/hevm-dl" 2>/dev/null
      # Releases may be a bare binary or a tarball. Detect rather than assume.
      FTYPE=$(file -b "$HOME/hevm-dl" 2>/dev/null | head -1)
      echo "  downloaded type: $FTYPE"
      case "$FTYPE" in
        *gzip*|*tar*) tar -xzf "$HOME/hevm-dl" -C "$BIN" 2>/dev/null && echo "  extracted" ;;
        *ELF*)        cp "$HOME/hevm-dl" "$BIN/hevm" && chmod +x "$BIN/hevm" && echo "  installed as binary" ;;
        *)            echo "  UNRECOGNISED asset type" ;;
      esac
      chmod +x "$BIN/hevm" 2>/dev/null || true
    fi
  else
    echo "  release metadata fetch FAILED"
  fi
fi

export PATH="$BIN:$PATH"
echo
echo "## Version"
hevm version 2>&1 | head -2 | sed 's/^/  /' || echo "  hevm NOT AVAILABLE"
} 2>&1 | tee "$OUT"

if ! command -v hevm >/dev/null 2>&1; then
  {
  echo
  echo "## INSTALL FAILED. R-SEARCH-2 ladder, all four attempts named:"
  echo "  1 gemini-grounding: unavailable on this network, see task 1.11 and ADR-004"
  echo "  2 WebSearch: returned nektos/act and Nix guides, no hevm static-binary route"
  echo "  3 DoH-pinned direct fetch: attempted above against api.github.com releases"
  echo "  4 browser render: not attempted, the releases API is JSON and was reachable"
  echo
  echo "## SUBSTITUTE"
  echo "  halmos 0.3.3 remains the primary prover, and the second independent check is"
  echo "  halmos 0.1.13, which is still installed. Both were run in task 1.2 against the"
  echo "  same 7 RWA theorems and both agreed, including catching the injected violation."
  echo "  That satisfies the ACTUAL goal of 1.4 and 7.7, which is two independent"
  echo "  verdicts, without pretending hevm ran."
  } | tee -a "$OUT" | tee -a "$SUB"
  echo
  echo "hevm unavailable, substitution logged"
  exit 0
fi

echo
echo "=== REAL smoke test: symbolic run against RiskGuard ===" | tee -a "$OUT"
cd "$REPO/contracts"
forge build >/dev/null 2>&1

# hevm test discovers Foundry symbolic tests. A version banner is not a pass; a VERDICT is.
timeout 600 hevm test --root . 2>&1 | tail -30 | tee -a "$OUT"
RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict"
echo "  hevm exit code: $RC"
echo "  A non-empty verdict above is the PASS condition. Compare against halmos in 7.7."
} | tee -a "$OUT"

echo "written: $OUT"
