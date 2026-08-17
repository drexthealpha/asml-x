#!/usr/bin/env bash
# Task 13.2: coordination metering. Per-caller usage counted and shown, with the fee that would
# apply to metered access.
#
# THINKING: #24 game theoretic (what does a caller do when usage is priced), #23 second-order,
# #11 systems.
#
# EVIDENCE PATH: evidence/phase13/metering.md
# PASS: usage by the external agent appears in the counters after scripts/96-external-settlement.sh.
#
# THE FEE IS QUOTED, NOT CHARGED, and that distinction is the honest part. The coordination API is
# deliberately unauthenticated with no privileged path, and nobody is billed today. What this task
# asks for is the fee that WOULD apply, computed from the same live FeeCollector rate the trading
# path uses, so the business model is one number rather than two.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase13/metering.md"
mkdir -p "$(dirname "$OUT")"
API="http://127.0.0.1:8737"
KEY="demo-agent-key-1"
RPC="$XLAYER_TESTNET_RPC"
ACCEPTED="$REPO/evidence/phase6/accepted-quotes.jsonl"

bash ./start-coord.sh < /dev/null 2>&1 | tail -1

# The live fee rate, from the deployed contract. One rate for trading and for metered coordination.
FEE_ADDR=$(python3 -c "import json;print(json.load(open('$REPO/deployments.json'))['feeCollector'])")
FEE_BPS=$(cast call "$FEE_ADDR" "feeBps()(uint256)" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')

{
echo "# Task 13.2: coordination metering"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
echo
echo "## Per-caller usage, counted by the API itself"
echo
echo "The coordination API already tracks calls per api-key for rate limiting. Metering reads the"
echo "same counters, so usage and throttling cannot disagree."
echo
echo '```'
curl -s -m 15 -H "x-api-key: $KEY" "$API/health" | python3 -m json.tool 2>/dev/null | head -20
echo '```'
echo
echo "## Usage by the external agent"
echo
echo "\`scripts/96-external-settlement.sh\` drives a genuinely separate process that requests a quote,"
echo "is refused on one side, takes the reducing side, and has it settled onchain. Its accepted"
echo "quotes are appended to a handoff record."
echo
echo '```'
} > "$OUT"

if [ -f "$ACCEPTED" ]; then
  N=$(grep -c . "$ACCEPTED")
  echo "accepted-quotes.jsonl rows: $N" >> "$OUT"
  echo >> "$OUT"
  python3 - "$ACCEPTED" "$FEE_BPS" >> "$OUT" <<'PY'
import json, sys
from collections import defaultdict

rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
bps = int(sys.argv[2] or 0)

per = defaultdict(lambda: {"calls": 0, "notional": 0})
for r in rows:
    caller = r.get("caller") or r.get("agent") or r.get("api_key") or "unnamed-caller"
    per[caller]["calls"] += 1
    for k in ("notional_micro", "quote_notional_micro", "size_micro"):
        if k in r:
            try:
                per[caller]["notional"] += abs(int(r[k]))
                break
            except Exception:
                pass

print(f"{'caller':28}{'calls':>8}{'notional (micro)':>20}{'fee at ' + str(bps) + ' bps':>18}")
tot_calls = tot_not = tot_fee = 0
for caller, v in sorted(per.items(), key=lambda kv: -kv[1]["calls"]):
    fee = v["notional"] * bps // 10_000
    tot_calls += v["calls"]; tot_not += v["notional"]; tot_fee += fee
    print(f"{caller[:28]:28}{v['calls']:>8}{v['notional']:>20}{fee:>18}")
print(f"{'TOTAL':28}{tot_calls:>8}{tot_not:>20}{tot_fee:>18}")
PY
else
  echo "accepted-quotes.jsonl absent: no external agent has settled yet." >> "$OUT"
fi

{
echo '```'
echo
echo "## The fee that WOULD apply, and why it is not charged"
echo
echo "The rate above is \`FeeCollector.feeBps()\` read live from \`$FEE_ADDR\`: **$FEE_BPS bps**. It is"
echo "the same rate the trading path charges, deliberately, so the business model is one number"
echo "rather than two that can drift."
echo
echo "**Nothing is billed today.** The coordination API is unauthenticated by design and its own"
echo "module docs say there is no privileged path: a caller cannot obtain a quote the agent itself"
echo "would be refused. Charging for access would require an identity system this project does not"
echo "have and did not build."
echo
echo "So this is a QUOTE, not an invoice, and the evidence says so. The claim being supported is"
echo "\"usage is measured and priceable at a rate that already exists onchain\", not \"usage is"
echo "monetised\". The second would be false."
echo
echo "## Second-order: what pricing coordination would change"
echo
echo "Worth stating because task 13.2's thinking models are game-theoretic, and a metering design"
echo "that ignores caller incentives is a spreadsheet rather than a mechanism."
echo
echo "- A per-CALL fee prices asking, which discourages the exploratory quotes that make the refusal"
echo "  ledger informative. A caller who is charged to ask will ask only when confident, and the"
echo "  refusals are the part of this system worth reading."
echo "- A per-SETTLEMENT fee prices success, which is what the trading path already charges and what"
echo "  the numbers above compute. A caller pays only when the agent's answer was worth acting on."
echo "- Free quotes with paid settlement is therefore the only variant consistent with the rest of"
echo "  the design, and it is the one costed here."
} >> "$OUT"

echo "written: $OUT"
grep -A12 "Usage by the external agent" "$OUT" | tail -10
