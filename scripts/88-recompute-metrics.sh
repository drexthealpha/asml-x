#!/usr/bin/env bash
# Task 5.1 onchain metrics. Recompute every counter the metrics panel shows, from the journal and
# from chain, and write them where the UI reads them.
#
# THINKING: #60 map-territory (the panel must not be able to disagree with the recompute, so the
# recompute WRITES the file the panel reads), #49 evidence, #41 algorithmic.
#
# DESIGN DECISION, recorded here because it is what makes the PASS condition meaningful: TASKS.md
# says "every counter reproduces from bash scripts/71-recompute-metrics.sh". A panel that computes
# its own counters in TypeScript and a script that computes them again in Python are two
# implementations that will drift, and the drift would be invisible. So there is ONE implementation:
# this script computes the counters and writes ui-v2/public/data/metrics.json, and the panel renders
# that file. Reproducing the panel is then the same operation as running this script.
#
# EVIDENCE PATH declared before code: evidence/phase5/metrics.txt, ui-v2/public/data/metrics.json
# PASS: every counter in the panel appears in the JSON this script wrote, and the onchain counters
# match a live read.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase5/metrics.txt"
mkdir -p "$(dirname "$OUT")"
RPC="$XLAYER_TESTNET_RPC"
# ADDRESSES COME FROM deployments.json, NEVER FROM A LITERAL.
# They used to be pinned here as strings from a Phase 2 deployment. Task 7.6 redeployed the stack and
# every "live chain read" below silently kept reading the old, abandoned contracts, producing numbers
# that were real reads of an irrelevant address. A chain read is not automatically a real read.
J="$REPO/deployments.json"
addr() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
GUARD=$(addr riskGuard)
VENUE=$(addr venue)
MARKET=$(addr marketId)
FEE=$(addr feeCollector)
echo "  addresses from deployments.json: guard=$GUARD venue=$VENUE fee=$FEE"

{
echo "Metrics recompute, task 5.1"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Live chain reads, so the onchain counters are not journal-derived"
} 2>&1 | tee "$OUT"

EXPOSURE=$(timeout 40 cast call "$GUARD" 'exposureOf(bytes32)(uint256)' "$MARKET" --rpc-url "$RPC" 2>&1 | tail -1 | awk '{print $1}')
# sumOfParts(), not totalGross(). The first version guessed the name and cast returned an error that
# the metrics file would have carried through as a blank. RiskGuard.sol:185 is the real getter, and
# its name is the point: gross is DERIVED as the sum of the per-market parts, which is what the
# halmos theorem check_grossAlwaysEqualsSumOfParts proves.
GROSS=$(timeout 40 cast call "$GUARD" 'sumOfParts()(uint256)' --rpc-url "$RPC" 2>&1 | tail -1 | awk '{print $1}')
CAP=$(timeout 40 cast call "$GUARD" 'maxPerMarket(bytes32)(uint256)' "$MARKET" --rpc-url "$RPC" 2>&1 | tail -1 | awk '{print $1}')
MAXGROSS=$(timeout 40 cast call "$GUARD" 'maxGross()(uint256)' --rpc-url "$RPC" 2>&1 | tail -1 | awk '{print $1}')
KILLED=$(timeout 40 cast call "$GUARD" 'killed()(bool)' --rpc-url "$RPC" 2>&1 | tail -1)
ORDERS=$(timeout 40 cast call "$VENUE" 'orderCount()(uint256)' --rpc-url "$RPC" 2>&1 | tail -1 | awk '{print $1}')
BLOCK=$(timeout 40 cast block-number --rpc-url "$RPC" 2>&1 | tail -1)
NONCE=$(timeout 40 cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1 | tail -1)

{
echo "  head block:                 $BLOCK"
echo "  guard.exposureOf(market):   $EXPOSURE wei"
echo "  guard.maxPerMarket(market): $CAP wei"
echo "  guard.totalGross():         $GROSS wei"
echo "  guard.maxGross():           $MAXGROSS wei"
echo "  guard.killed():             $KILLED"
echo "  venue.orderCount():         $ORDERS"
echo "  deployer nonce:             $NONCE  (total transactions ever sent by the agent's key)"
echo
echo "## Journal-derived counters"
} | tee -a "$OUT"

# The fee pass. Every number here is derived from eth_getLogs against the deployed FeeCollector, so
# the revenue the UI shows is the chain's answer rather than a counter the frontend incremented.
QUOTE_TOK=$(addr tQUOTE)
FEE_JSON="$HOME/.asml-fee-metrics.json"
# NO `|| echo '[]'` FALLBACK. The previous version had one, and it converted an RPC rejection into an
# empty log array that read downstream as "zero fees collected". If this fetcher fails it writes
# nothing and the metrics build fails, which is the only honest outcome for a revenue number.
if REPO="$REPO" RPC="$RPC" timeout 240 python3 "$REPO/scripts/fee_logs.py" "$FEE" "$QUOTE_TOK" > "$FEE_JSON" 2>"$HOME/.asml-fee-err"; then
  echo "  fee fetch: ok  $(python3 -c "import json;d=json.load(open('$FEE_JSON'));print(d['event_count'],'events,',d['total_fees_wei'],'wei,',d['windows_scanned'],'log windows')")" | tee -a "$OUT"
else
  echo "  fee fetch: FAILED  $(head -c 200 "$HOME/.asml-fee-err")" | tee -a "$OUT"
  rm -f "$FEE_JSON"
fi

EXPOSURE="$EXPOSURE" CAP="$CAP" GROSS="$GROSS" MAXGROSS="$MAXGROSS" KILLED="$KILLED" \
ORDERS="$ORDERS" BLOCK="$BLOCK" NONCE="$NONCE" \
FEE_ADDR="$FEE" FEE_JSON="$FEE_JSON" \
/home/zulab/.asml-venv/bin/python "$REPO/scripts/recompute_metrics.py" 2>&1 | tee -a "$OUT"
RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict, task 5.1"
if [ "${RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. Counters written to ui-v2/public/data/metrics.json, which is the file the"
  echo "  metrics panel renders. The panel cannot disagree with this script because there is only"
  echo "  one implementation."
  echo "  Reproduce: bash scripts/88-recompute-metrics.sh"
else
  echo "  RESULT: FAIL, exit $RC."
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit "${RC:-1}"
