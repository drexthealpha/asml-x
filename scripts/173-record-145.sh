#!/usr/bin/env bash
# Record C-1405 (task 14.5) into the evidence chain.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN="$REPO/evidence/CHAIN-OF-EVIDENCE.md"

for f in evidence/phase14/river-profit.txt docs/decisions/ADR-011-river-role.md; do
  if [ ! -s "$REPO/$f" ]; then
    echo "MISSING OR EMPTY: $f"; exit 1
  fi
done

# The row asserts the test was ANSWERED. Verify the file actually contains an answer rather than the
# too-few-samples bail-out, so a claim of "answered" can never outlive the run that answered it.
if ! grep -q "falsification test, answered" "$REPO/evidence/phase14/river-profit.txt"; then
  echo "The evidence file does not contain an answered falsification test. Refusing to record."
  exit 1
fi

if grep -q "C-1405" "$CHAIN"; then echo "already recorded"; exit 0; fi
TODAY=$(date -u '+%Y-%m-%d')

cat >> "$CHAIN" <<EOF
| C-1405 | ADR-011 made river a benchmark rather than a sidecar and named its own revisit condition: re-run it against a REALIZED PROFIT target once one exists, and reopen the sidecar question only if the margin survives the sample size. 14.4 created that target, so the test was run rather than deferred a second time. On 7 usable samples joined from settlements to the decisions that produced them, with 1 orphan DROPPED rather than defaulted because a defaulted feature vector against a real label is a fabricated training row, river scored 0.5714 against a majority baseline of 0.5714: a margin of ZERO predictions, one-sided binomial p 0.6531. The condition is NOT met and ADR-011 stands. THE CAVEAT IS RECORDED BEFORE THE NUMBER, not after: this venue's book is static so nothing settles on its own, the mid moves only because scripts/171 posts real orders to move it, and the profit label follows from which way it was moved. The target is a function of the sampling procedure and not of a market, so a WIN would not have licensed reopening the question either. ADR-011 asked for a measurement only an exogenous market can supply and this harness cannot supply one, which is a stated limit rather than a result dressed up as one | evidence/phase14/river-profit.txt, docs/decisions/ADR-011-river-role.md | bash scripts/172-river-profit-target.sh | DEMONSTRATED | 14.5 | $TODAY |
EOF

echo "appended C-1405"
grep -c "^| C-" "$CHAIN"
