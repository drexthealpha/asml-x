#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
A="$REPO/scripts/43-chain-add.sh"

bash "$A" C-122 \
  "Three independent sources agree on the cap-breach revert selector 0x3e2ed028: the Solidity error signature, the live deployed guard's eth_call revert data, and a local revm simulation which also decodes attempted=608e18 and cap=500e18" \
  "evidence/phase0/revm.txt" \
  "bash scripts/72-revm-smoke.sh && bash scripts/72b-revm-run.sh" DEMONSTRATED 1.13

bash "$A" C-128 \
  "Every one of 13 tool evidence files was DELETED and regenerated from its own command, 0 failures" \
  "evidence/phase0/reproducibility-audit.md" "bash scripts/82-repro-audit.sh" DEMONSTRATED 1.19

bash "$A" C-404 \
  "Seven malformed and adversarial inputs each produce a visible error state and no plausible number: out-of-range values render as invalid and are counted separately from malformed lines" \
  "evidence/phase4/phase4-redteam.md, evidence/phase4/redteam-fixtures.txt" \
  "bash scripts/80-ui-redteam.sh" DEMONSTRATED 4.9

echo "rows now: $(grep -c '^| C-' "$REPO/evidence/CHAIN-OF-EVIDENCE.md")"
