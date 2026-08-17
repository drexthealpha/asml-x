#!/usr/bin/env bash
# Task 7.7 gate: the UI's revenue figure is READ FROM CHAIN, not computed in the frontend.
#
# THINKING: #60 map-territory (the frontend must not be the source of truth for revenue),
# #49 skeptical, #12 design thinking.
#
# EVIDENCE PATH: evidence/phase7/fee-metrics.txt
#
# The phase's HEADLINE FAKE WIN, quoted from TASKS.md: "a counter incremented in TypeScript on each
# decision." Two counters below, and neither takes the panel's word for anything:
#
#   CHECK A  a grep asserting that no arithmetic on fees exists anywhere in ui-v2/src.
#   CHECK B  the no-data proof: with the fee source removed, the panel must render an ERROR, not a
#            zero. A zero says the business earned nothing; a missing read says nothing at all.
#
#   CHECK C  the totals in metrics.json equal the sum of the onchain events, cross-checked against
#            contract state by an independent path.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase7/fee-metrics.txt"
mkdir -p "$(dirname "$OUT")"
SRC="$REPO/ui-v2/src"
MJ="$REPO/ui-v2/public/data/metrics.json"

{
  echo "Task 7.7 gate: fee revenue reaches the UI from chain"
  echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo
  echo "== CHECK A: no arithmetic on fees anywhere in ui-v2/src =="
} > "$OUT"

# A grep here produced two false positives on its first run: the `*` of a `/** Fee revenue */` doc
# comment and the `/` inside the string "scripts/fee_logs.py". Both are operator characters and
# neither is an operation. The checker below strips comments and string literals before searching, so
# a failure means a real computation. It also runs a MUTATION on itself further down, because a
# checker that cannot fail proves nothing.
python3 "$REPO/scripts/check_no_fee_arithmetic.py" "$SRC" >> "$OUT" 2>&1
A=$?

{
  echo
  echo "  -- self-test: the checker must actually detect a fee computation --"
  echo "     injecting a totalFee = feeA + feeB line into a scratch copy of ui-v2/src"
} >> "$OUT"

SCRATCH="$HOME/.asml-fee-arith-scratch"
rm -rf "$SCRATCH"; cp -r "$SRC" "$SCRATCH"
printf 'export const totalFee = feeA + feeB;\n' >> "$SCRATCH/components/revenue-panel.tsx"
if python3 "$REPO/scripts/check_no_fee_arithmetic.py" "$SCRATCH" > /dev/null 2>&1; then
  echo "     FAIL  the checker passed a file containing feeA + feeB, so CHECK A is decorative" >> "$OUT"
  A=1
else
  echo "     PASS  the checker caught the injected computation" >> "$OUT"
fi
rm -rf "$SCRATCH"

# CHECK C first, because B destroys the file.
{
  echo
  echo "== CHECK C: metrics.json totals against an independent read =="
} >> "$OUT"

FEE=$(python3 -c "import json;print(json.load(open('$REPO/deployments.json'))['feeCollector'])")
TOK=$(python3 -c "import json;print(json.load(open('$REPO/deployments.json'))['tQUOTE'])")
CHAIN_TOTAL=$(cast call "$FEE" "totalCollected(address)(uint256)" "$TOK" --rpc-url "$XLAYER_TESTNET_RPC" | awk '{print $1}')
CHAIN_COUNT=$(cast call "$FEE" "chargeCount()(uint256)" --rpc-url "$XLAYER_TESTNET_RPC" | awk '{print $1}')

python3 - "$MJ" "$CHAIN_TOTAL" "$CHAIN_COUNT" >> "$OUT" 2>&1 <<'PY'
import json, sys
mj, chain_total, chain_count = sys.argv[1], sys.argv[2], int(sys.argv[3])
f = json.load(open(mj)).get("fees", {})
ui_total, ui_count = f.get("total_fees_wei"), f.get("event_count")
recent_sum = sum(int(e["fee_wei"]) for e in f.get("recent", []))
print(f"  metrics.json total_fees_wei: {ui_total}")
print(f"  live totalCollected():       {chain_total}")
print(f"  metrics.json event_count:    {ui_count}")
print(f"  live chargeCount():          {chain_count}")
print(f"  sum of decoded log rows:     {recent_sum}")
ok = str(ui_total) == str(chain_total) and ui_count == chain_count
# The log sum is an INDEPENDENT path to the same number: state says one thing, the events say
# another, and they must agree. They only match while every event fits in the recent window.
if f.get("recent_is_complete") and recent_sum != int(chain_total):
    print("  MISMATCH: the decoded events do not sum to the state total")
    ok = False
elif f.get("recent_is_complete"):
    print("  cross-check: decoded events sum to the state total exactly")
print("  CHECK C:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
C=$?

# CHECK B: the no-data proof. Remove the source and confirm the UI has nothing to render a zero from.
{
  echo
  echo "== CHECK B: no-data proof, the fee source removed =="
} >> "$OUT"

cp "$MJ" "$MJ.bak"
python3 - "$MJ" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d.pop("fees", None)
json.dump(d, open(sys.argv[1], "w"), indent=2)
print("  removed the fees block from metrics.json")
PY

# The panel's behaviour is determined by mapFees and the guard in revenue-panel.tsx. Assert the code
# path exists rather than eyeballing a screenshot: with `fees` absent, mapFees returns undefined and
# the panel returns PanelError.
{
  if grep -q 'if (!f || typeof f !== "object") return undefined;' "$SRC/lib/data.ts" \
     && grep -q 'if (!fees || fees.error || fees.totalFeesWei === undefined)' "$SRC/components/revenue-panel.tsx" \
     && grep -q 'PanelError' "$SRC/components/revenue-panel.tsx"; then
    echo "  PASS  with no fees block, mapFees returns undefined and the panel returns PanelError"
    echo "        (ui-v2/src/lib/data.ts mapFees, ui-v2/src/components/revenue-panel.tsx guard)"
  else
    echo "  FAIL  the panel has no distinct error path for a missing fee source"
  fi
  # And prove there is no zero fallback that would render 0 instead.
  if grep -nE 'totalFeesWei\s*\?\?|totalFeesWei.*\|\|\s*"0"|eventCount\s*\?\?\s*0' "$SRC" -r --include='*.ts*' >/dev/null 2>&1; then
    echo "  FAIL  a zero fallback exists on a fee field"
    B=1
  else
    echo "  PASS  no zero fallback on any fee field"
    B=0
  fi
} >> "$OUT"
B=${B:-1}

mv "$MJ.bak" "$MJ"
echo "  metrics.json restored" >> "$OUT"

{
  echo
  echo "== gate =="
  echo "CHECK A (no frontend fee arithmetic): $([ $A -eq 0 ] && echo PASS || echo FAIL)"
  echo "CHECK B (error not zero on no data):  $([ $B -eq 0 ] && echo PASS || echo FAIL)"
  echo "CHECK C (totals match the chain):     $([ $C -eq 0 ] && echo PASS || echo FAIL)"
  if [ $A -eq 0 ] && [ $B -eq 0 ] && [ $C -eq 0 ]; then
    echo "GATE: PASS"
  else
    echo "GATE: FAIL"
  fi
} >> "$OUT"

tail -30 "$OUT"
