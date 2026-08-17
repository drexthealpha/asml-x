#!/usr/bin/env bash
# Record C-1408 (task 14.7, the Phase 14 audit) into the evidence chain.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN="$REPO/evidence/CHAIN-OF-EVIDENCE.md"
G="$REPO/evidence/gates/phase14.md"

[ -s "$G" ] || { echo "MISSING: evidence/gates/phase14.md"; exit 1; }
grep -q "Verdict: \*\*PASS\*\*" "$G" || { echo "Phase 14 gate did not pass. Refusing to record."; exit 1; }

if grep -q "C-1408" "$CHAIN"; then echo "already recorded"; exit 0; fi
TODAY=$(date -u '+%Y-%m-%d')

cat >> "$CHAIN" <<EOF
| C-1408 | Phase 14 audited: 12 cited artefacts present and non-empty, 8 C-14xx rows, 115 workspace tests passing with 0 failing, and ZERO claim-to-artefact drift, where drift is checked by re-reading the NUMBERS a row asserts rather than only that its file exists. Five spans under one trace id with exactly one root; 7 non-zero settlements, every one of whose realized PnL was recomputed in Python from its own persisted fields and agreed with the Rust that wrote it, 0 failures. The report names what the phase does NOT establish before anything else: no profitability claim is possible from this data, the mid moves only because this project moves it so 14.5's labels are induced, the agent's hit rate is BELOW a coin flip and is shown on the landing page in the loss colour, the trace exports to stdout rather than a collector, and AggLayer remains INFERRED. It also records two things against itself: ADR-019's crates.io claim was untested and false, and ui-v2/src/components/learning-panel.tsx was destroyed by a write that did not read first, was unrecoverable from git or any transcript, and was REBUILT rather than recovered | evidence/gates/phase14.md | bash scripts/176-phase14-audit.sh | DEMONSTRATED | 14.7 | $TODAY |
EOF

echo "appended C-1408"
grep -c "^| C-" "$CHAIN"
