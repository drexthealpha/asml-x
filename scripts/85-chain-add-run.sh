#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
A="$REPO/scripts/43-chain-add.sh"

bash "$A" C-405 \
  "A 40-cycle agent run wrote 43 journal rows with 39 submitted transactions and 280 limit refusals in micro-units, and the pre-fix rows were split to a labelled legacy file with the boundary verified on each half" \
  "evidence/phase4/journal-split.txt, evidence/phase4/journal-scale-audit.txt, evidence/journal-legacy-2026-08-09.jsonl" \
  "bash scripts/84-journal-split.sh && bash scripts/77-journal-scale-audit.sh" DEMONSTRATED 4.8

bash "$A" C-406 \
  "The risk panel draws a real utilisation bar at MarketNotionalTooLarge 52.96 of 50.00, the per-market cap binding after exposure accumulated about 2.3 quote units per take" \
  "evidence/phase4/density-measured.md" \
  "bash scripts/78-ui-data.sh then serve ui-v2 and run scripts/measure-density.js" DEMONSTRATED 4.5

echo "rows now: $(grep -c '^| C-' "$REPO/evidence/CHAIN-OF-EVIDENCE.md")"
