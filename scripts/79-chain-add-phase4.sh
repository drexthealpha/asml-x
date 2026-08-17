#!/usr/bin/env bash
# Phase 4 chain-of-evidence rows, plus the Phase 1 rows that the final mutation round earned.
# A script file per E4.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

add() { bash "$REPO/scripts/43-chain-add.sh" "$@"; }

add C-232 \
  "Every one of the 37 surviving mutants is now dead: the final cargo-mutants run over risk-engine caught 91 and missed 0" \
  "evidence/phase0/cargo-mutants-after.txt" "bash scripts/66-remutate.sh" DEMONSTRATED 1.7

add C-121 \
  "The 9 Aug journal's 40 limit refusals all carry wei-scaled numbers, so it predates the wei_to_micro boundary conversion; the code is correct and the artifact is stale" \
  "evidence/phase4/journal-scale-audit.txt, evidence/phase4/journal-provenance.md" \
  "bash scripts/77-journal-scale-audit.sh" DEMONSTRATED 4.5

add C-401 \
  "The terminal UI reaches 46.63 percent ink coverage at 1920x1080 with 321 tabular-numeral cells across seven panels, and its largest empty rectangle is 8.10 percent of the viewport, which does NOT meet the 3.9 baseline" \
  "evidence/phase4/density-measured.md" \
  "bash scripts/78-ui-data.sh then serve ui-v2 and run scripts/measure-density.js" DEMONSTRATED 4.1

add C-402 \
  "With its data directory deleted the UI renders ZERO fabricated numbers: 11 of 11 top-bar metrics show an em dash and 7 of 7 panels name their missing source file" \
  "evidence/phase4/nodata-proof.md" \
  "cp -r ui-v2/dist /tmp/nodata && rm -rf /tmp/nodata/data && python3 -m http.server" DEMONSTRATED 4.7

add C-403 \
  "Every contract shown in the UI carries a provenance badge driven by the generated manifest rather than by a component, and all 7 are marked SELF-DEPLOYED" \
  "ui-v2/public/data/deployments.json, evidence/phase4/ui-data-staged.txt" \
  "bash scripts/78-ui-data.sh" DEMONSTRATED 4.6

echo "rows now: $(grep -c '^| C-' "$REPO/evidence/CHAIN-OF-EVIDENCE.md")"
