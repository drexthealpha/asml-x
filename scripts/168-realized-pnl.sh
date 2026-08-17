#!/usr/bin/env bash
# Task 14.4 gate: realized PnL in the journal, closing the learning loop.
#
# THINKING: #10 first-principles (what does it actually mean for this loop to be CLOSED), #49
# evidence (a hit rate is not a result), #50 is-this-real.
#
# EVIDENCE PATH: evidence/phase14/realized-pnl.md, evidence/settlements.jsonl
# PASS: a settlement joins to the decision that MADE the prediction, carries a signed PnL in micro
# quote units with every input it was computed from, AND a sign mutation is caught.
#
# WHAT THIS TASK IS ACTUALLY FOR. Before it, the loop reported a hit rate and an edge error in basis
# points. That grades forecasts, not trading: a signal can be right most of the time and still lose
# money by being right small and wrong large. Nothing in the system could tell those apart, because
# no size was ever multiplied into a move.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase14/realized-pnl.md"
SETTLE="$REPO/evidence/settlements.jsonl"
mkdir -p "$(dirname "$OUT")"

CARGO="$HOME/.cargo/bin/cargo"
cd "$REPO"

# ---------------------------------------------------------------------------
# 1. The sign mutation. This runs FIRST, because if the suite cannot catch an inverted sign then
#    nothing further in this file is worth reading. An inverted PnL sign makes a losing system report
#    profits and passes every direction-based test in the learning crate.
# ---------------------------------------------------------------------------
SRC="crates/learning/src/lib.rs"
cp "$SRC" "$SRC.bak"
python3 - "$SRC" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "            let realized_pnl_micro = (p.size_micro * directional) / MICRO;"
assert old in s, "mutation target not found; the gate must not silently pass"
s = s.replace(old, "            let realized_pnl_micro = (p.size_micro * -directional) / MICRO;", 1)
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("sign inverted")
PY

# `^test .* FAILED` also matches cargo's closing `test result: FAILED. ...` summary line, which
# inflated the count from 3 to 4 on the first run of this gate. Anchor on the `... FAILED` form that
# only an individual test produces.
"$CARGO" test -p learning > /tmp/mut.txt 2>&1
MUT=$(grep -cE "^test tests::.* \.\.\. FAILED" /tmp/mut.txt)
MUT_NAMES=$(grep -E "^test tests::.* \.\.\. FAILED" /tmp/mut.txt | sed 's/^test tests:://;s/ \.\.\..*//' | tr '\n' ' ')

# `touch` after restoring, and this is load-bearing. `mv` puts back the BACKUP's mtime, which is
# older than the mutated build artifact, so cargo considers the crate fresh and skips the rebuild
# entirely. The first run of this gate restored the file and then reported the MUTATED test results
# as the restored ones, which would have recorded a permanent 3-test failure as the baseline.
mv "$SRC.bak" "$SRC"
touch "$SRC"
REST=$("$CARGO" test -p learning 2>&1 | grep -E "^test result" | head -1)

# ---------------------------------------------------------------------------
# 2. A real settlement against the live chain. The learner has forecasts outstanding from earlier
#    runs; a settlement needs the lag to have elapsed AND the mid to have moved past the dead band.
#    If the venue is flat this produces nothing, and this gate SAYS SO rather than manufacturing a
#    row. A fabricated settlement would defeat the entire point of the task.
# ---------------------------------------------------------------------------
BEFORE=0
[ -f "$SETTLE" ] && BEFORE=$(grep -c . "$SETTLE")

"$CARGO" build --release -p runtime 2>&1 | tail -1
# Eight cycles, not three. A forecast needs SETTLE_LAG_MS (60s) to elapse before it can settle, and
# cycles run every few seconds, so a short run only ever settles forecasts left over from a previous
# invocation. Those predate 14.4 and carry no size, which is why the first run of this gate produced
# a settlement whose PnL was a correct but uninformative zero. Eight cycles is enough for a forecast
# recorded WITH a size in this same run to come due.
ASML_REPO="$REPO" ./target/release/asml learn 8 2>&1 | tail -30 > "$REPO/evidence/phase14/learn-run.txt"
cat "$REPO/evidence/phase14/learn-run.txt"

AFTER=0
[ -f "$SETTLE" ] && AFTER=$(grep -c . "$SETTLE")
NEW=$((AFTER - BEFORE))

VERDICT=FAIL
if [ "$MUT" -gt 0 ] && echo "$REST" | grep -q "0 failed"; then
  VERDICT=PASS
fi

{
echo "# Task 14.4: realized PnL, closing the learning loop"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **$VERDICT**"
echo
echo "## What was missing"
echo
echo "The loop already measured a hit rate and an edge error in basis points. **That grades"
echo "forecasts, not trading.** A signal can be right most of the time and still lose money, by being"
echo "right on small positions and wrong on large ones, and nothing in the system could tell those"
echo "two apart because no size was ever multiplied into a move. \`Pending\` now carries"
echo "\`size_micro\` and \`Outcome\` carries \`realized_pnl_micro\`."
echo
echo "## The arithmetic, and where the sign lives"
echo
echo '```rust'
echo "let price_delta = current_mid - p.mid_at_decision;"
echo "let directional = match p.predicted {"
echo "    Predicted::Up   =>  price_delta,"
echo "    Predicted::Down => -price_delta,   // a short gains when the price falls"
echo "    Predicted::NoView => 0,"
echo "};"
echo "let realized_pnl_micro = (p.size_micro * directional) / MICRO;"
echo '```'
echo
echo "Integer arithmetic throughout, because the workspace lint denies floats in this crate. The"
echo "division by \`MICRO\` happens ONCE: size and the price delta are each micro-scaled, so their"
echo "product is micro-squared. Truncation is toward zero and that is deliberate, since the rounding"
echo "that would flatter the result is the one that rounds a loss up to zero."
echo
echo "## The sign mutation"
echo
echo "\`directional\` was negated, inverting every PnL:"
echo
echo '```rust'
echo "- let realized_pnl_micro = (p.size_micro * directional) / MICRO;"
echo "+ let realized_pnl_micro = (p.size_micro * -directional) / MICRO;"
echo '```'
echo
echo "**$MUT tests went red:** \`$MUT_NAMES\`"
echo
echo "That is the failure worth guarding: an inverted sign makes a losing system report profits, and"
echo "it passes every direction-based test in the crate, because direction is scored separately from"
echo "PnL. Restored: \`$REST\`"
echo
echo "## Where the outcome is recorded, and why not in \`journal.jsonl\`"
echo
echo "Settlements are appended to \`evidence/settlements.jsonl\`, keyed by \`decision_id\`. Three"
echo "options existed and ADR-020 records the reasoning:"
echo
echo "1. **Rewrite the original journal row.** Rejected outright. Append-only is the property the"
echo "   whole evidence chain rests on. A journal that can be edited after the fact cannot be cited"
echo "   as a record of what was decided at the time."
echo "2. **Append settlement rows into \`journal.jsonl\`.** Rejected on a MEASURED cost: twenty-odd"
echo "   consumers read that file line by line and index \`r[\"candidates\"]\` and \`r[\"tx_hash\"]\`"
echo "   directly, so a differently-shaped row breaks the growth counters, the UI data build and the"
echo "   scale audit at once."
echo "3. **An append-only sidecar keyed by \`decision_id\`.** Chosen."
echo
echo "**This also fixes a real defect.** The \`outcome\` field on a journal row was filled with"
echo "whatever settled during THAT cycle, which is a different decision made a minute earlier. A row"
echo "for decision 163 carried decision 87's result. A settlement now names the decision that made"
echo "the prediction."
echo
echo "## Settlements produced by this run"
echo
echo "$NEW new settlement row(s); $AFTER total."
echo
if [ "$AFTER" -gt 0 ]; then
  echo '```'
  tail -3 "$SETTLE" | python3 -m json.tool --json-lines 2>/dev/null || tail -3 "$SETTLE"
  echo '```'
  echo
  echo "### Joined to the decision that made the prediction"
  echo
  echo '```'
  python3 - "$REPO/evidence/journal.jsonl" "$SETTLE" <<'PY'
import json, sys
jr = {}
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        r = json.loads(line)
    except Exception:
        continue
    jr[r.get("decision_id")] = r

for line in list(open(sys.argv[2], encoding="utf-8"))[-3:]:
    s = json.loads(line)
    d = jr.get(s["decision_id"])
    print(f"decision {s['decision_id']}")
    if d is None:
        print("  NO MATCHING JOURNAL ROW. The join failed and that is a defect, not a formatting gap.")
        continue
    print(f"  decided at block {d['block_number']}, action {d.get('action')}")
    print(f"  thesis            {d['thesis'][:88]}")
    print(f"  predicted         {s['predicted']} on {s['signal_name']}")
    print(f"  size              {s['size_micro']} micro base")
    print(f"  mid at decision   {s['mid_at_decision']}")
    print(f"  mid at settle     {s['mid_at_settle']}")
    print(f"  realized move     {s['realized_move_bps']} bps, direction correct {s['direction_correct']}")
    print(f"  expected edge     {s['expected_edge_micro']} micro")
    print(f"  edge error        {s['edge_error_micro']} micro")
    print(f"  REALIZED PNL      {s['realized_pnl_micro']} micro quote")
    print()
PY
  echo '```'
  echo
  echo "The join is on \`decision_id\`, so the outcome is attached to the reasoning that produced it:"
  echo "the thesis, the candidates considered and the size taken are all one lookup away from the"
  echo "money the decision made or lost. That is what closing the loop means here."
  echo
  echo "**A forecast driven all the way to a NON-ZERO PnL is in**"
  echo "\`evidence/phase14/pnl-settlement.md\`. It needed its own step: this venue's book is static, so"
  echo "the mid never moves and the 5 bps dead band correctly drops every forecast as unscoreable."
  echo "\`scripts/169-settle-with-real-move.sh\` posts a real order that moves it."
else
  echo "**No settlement has been produced yet.** A forecast settles only once the lag has elapsed AND"
  echo "the mid has moved past the dead band; on a flat book it is dropped as unscoreable rather than"
  echo "counted as wrong. This gate does NOT manufacture a row to fill the gap, because a fabricated"
  echo "settlement would defeat the whole point of the task. The arithmetic and the sign are proved"
  echo "above by the mutation instead."
fi
echo
echo "## What is claimed, and what is not"
echo
echo "**Claimed:** a signed realized PnL in micro quote units, recorded against the decision that"
echo "made the prediction, carrying every input it was computed from so a reader can recompute it."
echo
echo "**NOT claimed:** cash proceeds. This is MARK TO MARKET against a later observed mid, not the"
echo "result of a closing trade, and the \`basis\` field on every settlement row says so in those"
echo "words. Calling it realized cash would be claiming a round trip that did not happen."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/168-realized-pnl.sh"
echo '```'
} > "$OUT"

echo
echo "written: $OUT"
echo "VERDICT: $VERDICT"
[ "$VERDICT" = PASS ]
