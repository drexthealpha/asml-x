#!/usr/bin/env bash
# Prove the rewritten crossed-book test can actually FAIL.
#
# It replaced two tautologies. A replacement that also cannot fail would be the same defect wearing
# better prose, so the only thing that settles it is breaking the exact line it guards.
#
# THE MUTATION: remove the `.max(0)` floor from the crossing cost. On a crossed book `spread_bps` is
# negative, so the cost goes negative, `directional_edge - negative` grows, and a crossed book pays
# the agent to trade. That is the bug that actually shipped and that this file is named for.
#
# EVIDENCE PATH: evidence/phase18/crossed-book-mutation.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

CARGO="$HOME/.cargo/bin/cargo"
SRC="crates/decision-engine/src/lib.rs"
OUT="$REPO/evidence/phase18/crossed-book-mutation.txt"
mkdir -p "$(dirname "$OUT")"

{
echo "Crossed-book test, mutation proof"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

echo "=== baseline ==="
"$CARGO" test -p decision-engine --test crossed_book 2>&1 | grep -E "^test |test result" || true
BASE=$?

cp "$SRC" "$SRC.bak"
python3 - "$SRC" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "let crossing_cost = (notional * spread_bps.max(0)) / (2 * 10_000);"
assert old in s, "mutation target not found; the gate must not silently pass"
new = "let crossing_cost = (notional * spread_bps) / (2 * 10_000);"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("floor removed: spread_bps.max(0) -> spread_bps")
PY

echo
echo "=== mutated: the crossing cost may now go negative ==="
# `touch` after editing so cargo cannot serve a cached check. An earlier clippy run in this project
# reported exit 0 from cache while the log held a real error.
touch "$SRC"
"$CARGO" test -p decision-engine --test crossed_book > /tmp/cb-mut.txt 2>&1
MUT_RC=$?
grep -E "^test |test result|deepening the cross" /tmp/cb-mut.txt | head -8 || true
echo "mutated exit: $MUT_RC"

mv "$SRC.bak" "$SRC"
touch "$SRC"
echo
echo "=== restored ==="
"$CARGO" test -p decision-engine --test crossed_book > /tmp/cb-res.txt 2>&1
RES_RC=$?
grep -E "test result" /tmp/cb-res.txt || true
echo "restored exit: $RES_RC"

echo
if [ "$MUT_RC" -ne 0 ] && [ "$RES_RC" -eq 0 ]; then
  echo "VERDICT: PASS  the test goes RED on the mutation and GREEN when restored."
else
  echo "VERDICT: FAIL  mutated=$MUT_RC restored=$RES_RC"
fi
} 2>&1 | tee "$OUT"

grep -q "VERDICT: PASS" "$OUT"
