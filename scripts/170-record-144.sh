#!/usr/bin/env bash
# Record C-1403 (task 14.4) into the evidence chain.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN="$REPO/evidence/CHAIN-OF-EVIDENCE.md"

for f in evidence/phase14/realized-pnl.md evidence/phase14/pnl-settlement.md \
         evidence/settlements.jsonl docs/decisions/ADR-020-settlements-in-a-sidecar.md; do
  if [ ! -s "$REPO/$f" ]; then
    echo "MISSING OR EMPTY: $f. Refusing to append a row citing a file that is not there."
    exit 1
  fi
done

# The claim below asserts a NON-ZERO settlement exists. Check it rather than trusting the file was
# written when one did: an evidence row whose central number is zero would be a claim about a code
# path that never ran.
NONZERO=$(python3 - "$REPO/evidence/settlements.jsonl" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
print(sum(1 for r in rows if int(r["realized_pnl_micro"]) != 0))
PY
)
if [ "$NONZERO" -lt 1 ]; then
  echo "NO NON-ZERO SETTLEMENT ON DISK. Refusing to record the claim."
  exit 1
fi

if grep -q "C-1403" "$CHAIN"; then
  echo "already recorded"
  exit 0
fi

TODAY=$(date -u '+%Y-%m-%d')

cat >> "$CHAIN" <<EOF
| C-1403 | The learning loop is closed in MONEY, not only in direction: decision 176 predicted down on a 0.187500 base position, a real posted order moved the mid from 1.800000 to 2.000000, the call was wrong and it settled to a realized PnL of MINUS 37500 micro quote, recomputed independently in Python from the row's own persisted fields and agreeing with the Rust engine. The loop then acted on it, changing thin_book_penalty_bps from 400 to 425 after 5 settled outcomes because decisions had overestimated their own edge. Before this, the system measured hit rate and edge error in bps, which grades forecasts rather than trading: a signal can be right most of the time and lose by being right small and wrong large. Inverting the PnL direction sign turns 3 tests red, the failure that would otherwise make a losing system report profits while passing every direction-based test. THE FIGURE IS A LOSS AND IS LEFT AS IT CAME OUT, and it is MARK TO MARKET against a later observed mid, never cash proceeds, which every settlement row states in its own basis field. The mid move was caused deliberately on a self-deployed stand-in venue to exercise a path a static book never reaches, and the evidence says so rather than implying an exogenous forecast | evidence/phase14/realized-pnl.md, evidence/phase14/pnl-settlement.md, evidence/settlements.jsonl | bash scripts/168-realized-pnl.sh && bash scripts/169-settle-with-real-move.sh | DEMONSTRATED | 14.4 | $TODAY |
| C-1404 | A journal row's outcome field used to carry whatever settled during THAT cycle, which is a different decision made a minute earlier: decision 163's row carried decision 87's result, so anyone reading a row and taking outcome as that row's outcome read another decision's number. FIXED, not documented: outcomes now live in an append-only sidecar keyed by decision_id, carrying every input the PnL was computed from so a reader can recompute it rather than trust it. Rewriting the original row was rejected because append-only is the property the whole evidence chain rests on, and adding settlement rows to journal.jsonl was rejected on a MEASURED cost, since twenty-odd consumers index r[candidates] and r[tx_hash] directly and would break at once | docs/decisions/ADR-020-settlements-in-a-sidecar.md, evidence/settlements.jsonl | bash scripts/168-realized-pnl.sh | DEMONSTRATED | 14.4 | $TODAY |
EOF

echo "appended C-1403, C-1404 (non-zero settlements on disk: $NONZERO)"
grep -c "^| C-" "$CHAIN"
