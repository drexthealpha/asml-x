#!/usr/bin/env bash
# Task 14.4, part two: drive a forecast all the way to a NON-ZERO realized PnL.
#
# THINKING: #50 is-this-real, #22 inversion (what market condition does the settlement path need,
# and does this venue ever produce it), #49 evidence.
#
# THE PROBLEM THIS SOLVES. scripts/168 proved the PnL arithmetic by mutation, but every settlement it
# could produce came out as zero, for two different and both-honest reasons:
#
#   1. Forecasts left over from before 14.4 carry no size, so their PnL is correctly zero.
#   2. The seeded book is STATIC. The mid never moves, so every new forecast is dropped by the dead
#      band as unscoreable rather than settled. That is the learner working: a market that did not
#      move cannot judge a directional call.
#
# So the settlement path exists, is tested, and had never once run end to end on a real position.
# Recording that as done would be the exact failure this project keeps catching in itself.
#
# WHAT THIS DOES, STATED PLAINLY. The venue is a SELF-DEPLOYED STAND-IN, as labelled throughout this
# repo, and this script posts a real order to it that moves the mid. That is a genuine onchain price
# move, in a real transaction, on a market this project controls. The PnL computed from it is real
# arithmetic over a real move. It is NOT a claim that the agent predicted an exogenous market: the
# move was caused deliberately to exercise the settlement path, and the evidence says so.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
VENUE=$(a venue); BASE=$(a tBASE); QUOTE=$(a tQUOTE)
SETTLE="$REPO/evidence/settlements.jsonl"
OUT="$REPO/evidence/phase14/pnl-settlement.md"

CARGO="$HOME/.cargo/bin/cargo"
cd "$REPO"
"$CARGO" build --release -p runtime 2>&1 | tail -1

mid_now() {
  ASML_REPO="$REPO" ./target/release/asml learn 1 2>&1 | grep -oE "mid [0-9]+" | head -1
}

BEFORE=0
[ -f "$SETTLE" ] && BEFORE=$(grep -c . "$SETTLE")

echo "=== 1. record a forecast that carries a size ==="
ASML_REPO="$REPO" ./target/release/asml learn 2 2>&1 | grep -E "^cycle|pending" | tail -3

echo
echo "=== 2. move the mid with a real order ==="
echo "    A bid at 2.30 becomes the best bid, lifting the mid well past the 5 bps dead band."
echo -n "  bid 3 tBASE @ 2.30: "
cast send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" \
  "$BASE" "$QUOTE" true 3000000000000000000 2300000000000000000 \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['status'],d['transactionHash'])" 2>/dev/null || echo FAIL

echo
echo "=== 3. wait out the 60s settlement lag ==="
echo "    The lag is not negotiable: a forecast scored against the price it was made at is scored"
echo "    against itself, and would report a perfect hit rate for a signal carrying no information."
sleep 70

echo
echo "=== 4. settle ==="
ASML_REPO="$REPO" ./target/release/asml learn 3 2>&1 | grep -E "settled decision|^cycle" | tail -6

AFTER=0
[ -f "$SETTLE" ] && AFTER=$(grep -c . "$SETTLE")
NEW=$((AFTER - BEFORE))
echo
echo "new settlements: $NEW"

python3 - "$SETTLE" "$REPO/evidence/journal.jsonl" "$OUT" "$NEW" <<'PY'
import json, sys, datetime

settle_path, journal_path, out_path, new = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

rows = [json.loads(l) for l in open(settle_path, encoding="utf-8") if l.strip()]
nonzero = [r for r in rows if int(r["realized_pnl_micro"]) != 0]

jr = {}
for line in open(journal_path, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    jr[d.get("decision_id")] = d

verdict = "PASS" if nonzero else "FAIL"
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

L = []
w = L.append
w("# Task 14.4, part two: a forecast settled to a non-zero realized PnL")
w("")
w(f"Run {now}. Verdict: **{verdict}**")
w("")
w(f"{len(rows)} settlement(s) recorded, {len(nonzero)} with a non-zero PnL, {new} new in this run.")
w("")
w("## Why this needed its own step")
w("")
w("`scripts/168-realized-pnl.sh` proved the arithmetic by inverting the sign and watching three")
w("tests go red. What it could not do was run the path end to end on a real position, for two")
w("reasons that are both the system working correctly:")
w("")
w("1. Forecasts recorded before 14.4 carry no size, so their PnL is correctly zero.")
w("2. The seeded book is **static**. The mid never moved, so every new forecast was dropped by the")
w("   5 bps dead band as unscoreable rather than settled. A market that did not move cannot judge a")
w("   directional call, and scoring it would manufacture a hit rate out of noise.")
w("")
w("So the settlement path was tested and had never once executed on a real position. Recording")
w("14.4 as done on that basis would have been a green nobody had tried to break.")
w("")
w("## What was done, stated plainly")
w("")
w("The venue is a **self-deployed stand-in**, as labelled throughout this repo. A real order was")
w("posted to it that moves the mid past the dead band. That is a genuine onchain price move in a")
w("real transaction, and the PnL below is real arithmetic over it.")
w("")
w("**This is NOT a claim that the agent predicted an exogenous market.** The move was caused")
w("deliberately, to exercise a code path that this venue would otherwise never reach. What is")
w("demonstrated is that a decision's outcome flows back to the decision that made it, carrying a")
w("signed figure in money rather than only a direction.")
w("")

if nonzero:
    s = nonzero[-1]
    d = jr.get(s["decision_id"])
    w("## The settled decision")
    w("")
    w("```")
    w(f"decision {s['decision_id']}")
    if d:
        w(f"  decided at block   {d['block_number']}")
        w(f"  action             {d.get('action')}")
        w(f"  thesis             {d['thesis'][:86]}")
    else:
        w("  NO MATCHING JOURNAL ROW: the join failed, which is a defect not a formatting gap.")
    w(f"  predicted          {s['predicted']} on {s['signal_name']}")
    w(f"  size               {s['size_micro']} micro base")
    w(f"  mid at decision    {s['mid_at_decision']}")
    w(f"  mid at settle      {s['mid_at_settle']}")
    w(f"  realized move      {s['realized_move_bps']} bps")
    w(f"  direction correct  {s['direction_correct']}")
    w(f"  expected edge      {s['expected_edge_micro']} micro")
    w(f"  edge error         {s['edge_error_micro']} micro")
    w(f"  REALIZED PNL       {s['realized_pnl_micro']} micro quote")
    w("```")
    w("")
    size = int(s["size_micro"])
    d0, d1 = int(s["mid_at_decision"]), int(s["mid_at_settle"])
    delta = d1 - d0
    signed = delta if s["predicted"] == "up" else -delta
    check = (size * signed) // 1_000_000
    w("Recomputed from the row's own fields:")
    w("")
    w("```")
    w(f"  price delta      {d1} - {d0} = {delta}")
    w(f"  direction        predicted {s['predicted']}, so signed delta = {signed}")
    w(f"  pnl              {size} * {signed} / 1000000 = {check}")
    w(f"  recorded         {s['realized_pnl_micro']}")
    w(f"  agree            {check == int(s['realized_pnl_micro'])}")
    w("```")
    w("")
    if int(s["realized_pnl_micro"]) < 0:
        w("**The PnL is negative, and that is left exactly as it came out.** The agent was short and")
        w("the mid was pushed up, so the position lost. A gate that only ever demonstrated a profit")
        w("would be selecting its evidence; the loop is closed whichever way the number falls, and a")
        w("system that can only record its wins is not measuring anything.")
    else:
        w("The PnL is positive here. It would have been recorded identically had it been negative:")
        w("the sign is carried through, and `a_wrong_call_produces_a_negative_pnl` pins that.")
else:
    w("## No non-zero settlement was produced")
    w("")
    w("The mid did not move past the dead band within the lag, so nothing settled to a real figure.")
    w("**No row is manufactured to fill this gap.** A fabricated settlement would defeat the whole")
    w("point of the task, and this file reports the absence instead.")

w("")
w("## Reproduce")
w("")
w("```")
w("bash scripts/169-settle-with-real-move.sh")
w("```")

open(out_path, "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
print(f"written: {out_path}")
print(f"VERDICT: {verdict}")
raise SystemExit(0 if verdict == "PASS" else 1)
PY
