#!/usr/bin/env bash
# Phase 5 chain-of-evidence rows. One script rather than a shell loop, because the loop passed its
# fields through `read` and the ids arrived empty.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
A="$REPO/scripts/43-chain-add.sh"

bash "$A" C-500 \
  "Every metrics-panel counter is written by one script and rendered without recomputation, so reproducing the panel and running the script are the same operation" \
  "evidence/phase5/metrics.txt, ui-v2/public/data/metrics.json" \
  "bash scripts/88-recompute-metrics.sh" DEMONSTRATED 5.1

bash "$A" C-501 \
  "Zero unexplained numeric literals in the UI render paths: all 329 are layout, config, a domain bound, an index or a documented reference" \
  "evidence/phase5/no-magic-numbers.txt" \
  "bash scripts/87-assert-no-magic-numbers.sh" DEMONSTRATED 5.2

bash "$A" C-502 \
  "The journal feed virtualises 500 rows with 28 mounted and a 34.8ms median two-frame latency across a 40-jump burst" \
  "evidence/phase5/journal-stream.md" \
  "bash scripts/89-journal-load-test.sh then paste scripts/measure-feed.js in the console" DEMONSTRATED 5.3

bash "$A" C-503 \
  "The same order was judged against a crypto market and an RWA market in three live vault states: healthy approves both, issuer-paused and oracle-divergence refuse only the RWA market and name an RWA-specific cause" \
  "evidence/phase5/comparator/, ui-v2/public/data/comparator.json" \
  "bash scripts/90-comparator-states.sh" DEMONSTRATED 5.4

bash "$A" C-504 \
  "The comparator gate asserts five properties including the control that the crypto market approved in every state, so a difference cannot come from anything but the instrument" \
  "evidence/phase5/comparator-gate.txt" \
  "bash scripts/91-assert-comparator-states.sh" DEMONSTRATED 5.5

bash "$A" C-505 \
  "The learning panel states its sample size on every row and labels anything below 30 settled outcomes as too small to read as a hit rate" \
  "ui-v2/src/components/learning-panel.tsx, docs/decisions/ADR-011-river-role.md" \
  "bash scripts/78-ui-data.sh then open the Chain view" DEMONSTRATED 5.6

bash "$A" C-506 \
  "A journal where every cycle scored exactly one candidate is flagged as a defect on all 43 rows rather than rendered as a decision, with a different sentence for the zero-candidate case" \
  "evidence/phase5/phase5-redteam.md" \
  "bash scripts/92-phase5-redteam.sh then open http://localhost:4177" DEMONSTRATED 5.7

echo "rows now: $(grep -c '^| C-' "$REPO/evidence/CHAIN-OF-EVIDENCE.md")"
