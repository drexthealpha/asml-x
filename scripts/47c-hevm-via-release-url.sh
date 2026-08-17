#!/usr/bin/env bash
# Task 1.4, route two. The GitHub API path 301s under --resolve pinning, so skip the API
# entirely and use github.com's /releases/latest/download/ redirect, which resolves
# normally on this machine (github.com is NOT blocked, only api.github.com and okx.com are).
#
# THINKING: #16 lateral (stop fighting the API, use the download endpoint that needs no
# API), #50 empirical (probe the actual asset names rather than guessing one).
#
# R-SEARCH-3 compliance: this is a DIFFERENT ROUTE after one identified failure
# ("Moved Permanently" from the pinned API host), not a retry of the same call.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/hevm.txt"
SUB="$REPO/evidence/phase0/tool-substitutions.md"
mkdir -p "$(dirname "$OUT")" "$(dirname "$SUB")"
BIN="$HOME/.local/bin"; mkdir -p "$BIN"
export PATH="$BIN:$PATH"

{
echo "hevm install, task 1.4, route two"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Why route two"
echo "  Route one used api.github.com pinned to a DoH-resolved IP and got"
echo "  'Moved Permanently': the edge IP does not serve that vhost directly. github.com"
echo "  itself resolves fine here, so /releases/latest/download/ needs no API call."
echo
echo "## Probing candidate asset names against the latest-download redirect"

# hevm publishes per-platform binaries. Try the documented naming patterns in order and
# report the HTTP status for each, so a 404 is visible rather than silent.
for NAME in hevm-x86_64-linux hevm-linux-x86_64 hevm-x86_64-linux.tar.gz hevm-linux-amd64; do
  URL="https://github.com/ethereum/hevm/releases/latest/download/$NAME"
  CODE=$(curl -sSL --max-time 90 -o "$HOME/hevm-try" -w '%{http_code}' "$URL" 2>/dev/null)
  SIZE=$(stat -c%s "$HOME/hevm-try" 2>/dev/null || echo 0)
  printf '  %-28s HTTP %s  bytes %s\n' "$NAME" "$CODE" "$SIZE"
  if [ "$CODE" = "200" ] && [ "${SIZE:-0}" -gt 100000 ]; then
    FTYPE=$(file -b "$HOME/hevm-try" 2>/dev/null | head -1)
    echo "    type: $FTYPE"
    case "$FTYPE" in
      *gzip*|*tar*) tar -xzf "$HOME/hevm-try" -C "$BIN" 2>/dev/null; ;;
      *ELF*)        cp "$HOME/hevm-try" "$BIN/hevm"; ;;
    esac
    chmod +x "$BIN/hevm" 2>/dev/null || true
    if command -v hevm >/dev/null 2>&1; then
      echo "    INSTALLED: $(hevm version 2>&1 | head -1)"
      break
    fi
  fi
done

echo
echo "## Result"
if command -v hevm >/dev/null 2>&1; then
  echo "  hevm available: $(hevm version 2>&1 | head -1)"
else
  echo "  hevm still unavailable after route two"
fi
} 2>&1 | tee "$OUT"

if ! command -v hevm >/dev/null 2>&1; then
  {
  echo
  echo "## hevm: SUBSTITUTED, all four R-SEARCH-2 attempts named"
  echo
  echo "  1 gemini-grounding: unavailable on this network (task 1.11, ADR-004)."
  echo "  2 WebSearch: returned nektos/act and Nix installation guides. No static-binary"
  echo "    route for ethereum/hevm surfaced."
  echo "  3 DoH-pinned direct fetch: api.github.com returns 'Moved Permanently' when"
  echo "    pinned to a DoH-resolved edge IP. The releases/latest/download redirect was"
  echo "    then probed with four documented asset names, statuses recorded above."
  echo "  4 Browser render: not attempted. The blocker is an HTTP redirect and asset"
  echo "    naming, not JavaScript rendering, so a browser adds nothing here."
  echo
  echo "  SUBSTITUTE, and why it satisfies the real goal:"
  echo "  Tasks 1.4 and 7.7 exist to get TWO INDEPENDENT PROVER VERDICTS on the cap"
  echo "  theorem. That is achieved with halmos 0.1.13 and halmos 0.3.3, which are"
  echo "  separate installs on separate Python interpreters (system 3.10 and uv 3.12)"
  echo "  with different solver stacks. Task 1.2 ran both against the same 7 RWA"
  echo "  theorems: both passed all 7, and both caught the injected pause-refusal"
  echo "  violation. Recorded in evidence/phase0/halmos.txt."
  echo
  echo "  What this substitution does NOT give us, stated plainly: two different"
  echo "  SYMBOLIC ENGINES. Two versions of halmos share an architecture and could share"
  echo "  a blind spot. The claim in 7.7 will therefore be 'two independent prover"
  echo "  versions agree', not 'two independent engines agree'. That distinction is"
  echo "  material and will not be blurred in the docs."
  } | tee -a "$OUT" | tee -a "$SUB"
  echo
  echo "hevm SUBSTITUTED, logged with the honest limitation"
  exit 0
fi

echo
echo "=== real smoke test against RiskGuard ===" | tee -a "$OUT"
cd "$REPO/contracts" && forge build >/dev/null 2>&1
timeout 500 hevm test --root . 2>&1 | tail -25 | tee -a "$OUT"
echo "written: $OUT"
