#!/usr/bin/env bash
# The agent, on mainnet, executing through REAL pools.
#
# This is the run that retires the last of the seeded data. Every prior journal entry was decided
# against an order book this project deployed; from here the decisions are still ours and the
# EXECUTION is not.
#
# The runtime reads deployments.json, so it is pointed at mainnet for the duration and restored
# afterwards: the testnet file is cited by every Phase 7 to 10 artifact and must survive.
#
# EVIDENCE PATH: evidence/phase19/real-agent-run.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CYCLES="${CYCLES:-6}"
RPC="https://rpc.xlayer.tech"
OUT="$REPO/evidence/phase19/real-agent-run.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

MJ="$REPO/deployments-mainnet.json"
TJ="$REPO/deployments.json"

cp "$TJ" "$TJ.testnet-backup"
cp "$MJ" "$TJ"
trap 'cp "$TJ.testnet-backup" "$TJ" 2>/dev/null; rm -f "$TJ.testnet-backup"' EXIT

JBEFORE=$(grep -c . "$REPO/evidence/journal.jsonl" 2>/dev/null || echo 0)

# THE AGENT MUST SEE ITS OWN BALANCE. Without these two the runtime falls back to the venue path's
# accounting, which assumed 1,000 spendable units. That assumption was invisible while the quote
# token was one this project minted; against real USDT it made the agent size every order roughly
# 5,000 times larger than it could pay for, and every swap reverted.
SPEND_TOKEN=$(cd "$REPO/scripts" && python3 -c "import tokens;print(tokens.address('USDT'))") || exit 1
SPEND_HOLDER=$(python3 -c "import json;print(json.load(open('$MJ'))['routerExecutor'])")

cd "$REPO"
echo "=== $CYCLES cycles, chain 196, execution through real pools ==="
echo "spending  USDT $SPEND_TOKEN"
echo "held by   $SPEND_HOLDER"
ASML_EXECUTION=router ASML_RPC="$RPC" ASML_CHAIN_ID=196 ASML_REPO="$REPO" \
  ASML_SPEND_TOKEN="$SPEND_TOKEN" ASML_SPEND_HOLDER="$SPEND_HOLDER" \
  ./target/release/asml run "$CYCLES" 2>&1 | tail -30

JAFTER=$(grep -c . "$REPO/evidence/journal.jsonl" 2>/dev/null || echo 0)
cp "$TJ.testnet-backup" "$TJ"; rm -f "$TJ.testnet-backup"; trap - EXIT

echo
echo "journal $JBEFORE -> $JAFTER"
echo
echo "=== real swaps recorded ==="
if [ -f "$REPO/evidence/phase19/real-swaps.jsonl" ]; then
  python3 -c "
import json
for line in open('$REPO/evidence/phase19/real-swaps.jsonl'):
    d = json.loads(line)
    print(f\"  #{d['decision_id']:<5} {d['from']} -> {d['to']}  via {d['venues']}\")
    print(f\"         {d['explorer']}\")
"
else
  echo "  none yet"
fi
