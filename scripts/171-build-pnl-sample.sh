#!/usr/bin/env bash
# Task 14.5 support: build a sample of settled decisions carrying realized PnL.
#
# THINKING: #49 evidence (a benchmark with no target variable is not a benchmark), #61 circle of
# competence (what can a sample of this size actually support), #50 empirical.
#
# ADR-011 made river a BENCHMARK ONLY and named its own falsification test: after realized PnL lands,
# re-run river against a PROFIT target, and if it beats the majority baseline by a margin that
# survives the sample size, the sidecar question is live again. 14.4 landed the PnL. This builds the
# sample that test needs.
#
# HOW THE MOVES ARE MADE, AND WHY IT MATTERS TO SAY SO. This venue's book is static, so nothing ever
# settles on its own. Each round posts a real order that moves the mid, ALTERNATING up and down. The
# alternation is not cosmetic: the agent predicts Down almost every cycle here, so moving the mid one
# way every time would make the profit label CONSTANT, and a constant target is unlearnable by
# construction. A benchmark run against it would report the majority baseline as unbeatable and mean
# nothing at all.
#
# The consequence is stated plainly in the evidence and is the central caveat of 14.5: these labels
# are INDUCED BY THIS SCRIPT, not observed from an exogenous market.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

ROUNDS="${1:-8}"
RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
VENUE=$(a venue); BASE=$(a tBASE); QUOTE=$(a tQUOTE)
SETTLE="$REPO/evidence/settlements.jsonl"

CARGO="$HOME/.cargo/bin/cargo"
cd "$REPO"
"$CARGO" build --release -p runtime 2>&1 | tail -1

post() { # side_is_bid price_wei
  cast send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" \
    "$BASE" "$QUOTE" "$1" 3000000000000000000 "$2" \
    --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['status'])" 2>/dev/null || echo FAIL
}

BEFORE=0
[ -f "$SETTLE" ] && BEFORE=$(grep -c . "$SETTLE")
echo "settlements before: $BEFORE"

r=0
while [ "$r" -lt "$ROUNDS" ]; do
  echo
  echo "=== round $r ==="
  ASML_REPO="$REPO" ./target/release/asml learn 2 2>&1 | grep -E "^cycle" | tail -1

  if [ $((r % 2)) -eq 0 ]; then
    # Lift the mid: a bid above the current best.
    echo -n "  bid  3 tBASE @ 2.40: "; post true 2400000000000000000
  else
    # Drop it: an ask below the current best.
    echo -n "  ask  3 tBASE @ 1.20: "; post false 1200000000000000000
  fi

  sleep 70
  ASML_REPO="$REPO" ./target/release/asml learn 2 2>&1 | grep -E "settled decision" | tail -4

  AFTER=0
  [ -f "$SETTLE" ] && AFTER=$(grep -c . "$SETTLE")
  echo "  settlements now: $AFTER"
  r=$((r + 1))
done

AFTER=0
[ -f "$SETTLE" ] && AFTER=$(grep -c . "$SETTLE")
echo
echo "settlements after: $AFTER (added $((AFTER - BEFORE)))"

python3 - "$SETTLE" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
pnl = [int(r["realized_pnl_micro"]) for r in rows]
wins = sum(1 for p in pnl if p > 0)
losses = sum(1 for p in pnl if p < 0)
flat = sum(1 for p in pnl if p == 0)
print(f"total {len(rows)}  profitable {wins}  losing {losses}  zero {flat}")
print(f"majority class {max(wins, losses + flat)}/{len(rows)}")
PY
