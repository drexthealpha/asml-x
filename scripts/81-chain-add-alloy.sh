#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

bash "$REPO/scripts/43-chain-add.sh" C-120 \
  "alloy 2.3.0 and the hand-rolled client return IDENTICAL bytes for RiskGuard.sumOfParts() at the same pinned block, and alloy independently reports chain id 1952" \
  "evidence/phase0/alloy.txt" \
  "bash scripts/71-alloy-smoke.sh && bash scripts/71b-alloy-run.sh" DEMONSTRATED 1.12

bash "$REPO/scripts/43-chain-add.sh" C-127 \
  "Every one of the 47 rows in the tool ledger carries a status and a reason, and ZERO remain PENDING" \
  "evidence/TOOL-USAGE.md" \
  "grep -cE '^. [^|]+ . PENDING' evidence/TOOL-USAGE.md" DEMONSTRATED 1.18

echo "rows now: $(grep -c '^| C-' "$REPO/evidence/CHAIN-OF-EVIDENCE.md")"
