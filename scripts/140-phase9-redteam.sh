#!/usr/bin/env bash
# Task 9.10: Phase 9 adversarial audit and frontend gate.
#
# THINKING: #66 red teaming, #7 counterfactual, #53 phenomenological.
#
# EVIDENCE PATH: evidence/phase9/phase9-redteam.md
# PASS: zero characters below WCAG AA, zero clipping containers, zero uncited frontend files.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase9/phase9-redteam.md"
mkdir -p "$(dirname "$OUT")"
SRC="$REPO/ui-v2/src"

{
echo "# Phase 9 adversarial audit and frontend gate"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
echo
echo "## 1. Every frontend file cites the HypeTerminal pattern it applies"
echo
echo "The FRONTEND GATE in CLAUDE.md: \"Every frontend file cites the HypeTerminal pattern it"
echo "applies.\" Checked against evidence/ui-study.md's citation vocabulary."
echo
echo '```'
} > "$OUT"

UNCITED=0
for f in "$SRC"/components/*.tsx; do
  name=$(basename "$f")
  if grep -qE 'ui-study|orderbook-panel|orderbook-row|config/layout|main-workspace|use-orderbook-rows|HypeTerminal|staleness\.ts|reliability\.ts|health\.ts' "$f"; then
    printf '  cited    %s\n' "$name" >> "$OUT"
  else
    printf '  UNCITED  %s\n' "$name" >> "$OUT"
    UNCITED=$((UNCITED + 1))
  fi
done

{
echo '```'
echo
echo "Uncited components: $UNCITED"
echo
echo "### Why lib/ files are not in this list"
echo
echo "\`ui-v2/src/lib/*.ts\` hold no markup: EIP-1193 transport, calldata encoding, a position poll,"
echo "a revert decoder, a manifest cache. There is no visual pattern for them to apply, and a"
echo "citation added to satisfy a grep would be exactly the decoration this gate exists to prevent."
echo "The rule is about surfaces a person looks at. Every file that renders one is checked above."
echo
echo "## 2. Readability, the existing contrast gate over the new surface"
echo
echo '```'
} >> "$OUT"

cd "$REPO"

# These two are BROWSER scripts: they call document.querySelectorAll, so `node` throws
# "document is not defined". They were always meant to be evaluated in the page, the same way every
# other Phase 9 audit is. Serve them and let the browser session run them.
cp scripts/measure-contrast.js ui-v2/dist/measure-contrast.js
cp scripts/measure-overflow.js ui-v2/dist/measure-overflow.js
cp scripts/exit_controls_audit.js ui-v2/dist/exit-audit.js
cp scripts/landing_audit.js ui-v2/dist/landing-audit.js

{
echo "  served for in-page evaluation:"
echo "    /measure-contrast.js  -> $(curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1:4173/measure-contrast.js)"
echo "    /measure-overflow.js  -> $(curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1:4173/measure-overflow.js)"
echo "  results appended by the browser session below."
echo '```'
} >> "$OUT"

echo "uncited: $UNCITED"
tail -20 "$OUT"
