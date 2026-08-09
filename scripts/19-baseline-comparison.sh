#!/usr/bin/env bash
# Task 4.3: honest comparison against a naive baseline.
#
# Anti-cherry-pick control: the window is declared and written to evidence BEFORE
# either mode runs, so the comparison cannot be re-rolled until it flatters us.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$PATH"

EVID="$REPO/evidence/baseline-comparison"
mkdir -p "$EVID"
RPC="$XLAYER_TESTNET_RPC"
CYCLES=4

# --- declare the window FIRST ---
WINDOW_START=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
BLOCK_START=$(cast block-number --rpc-url "$RPC")
cat > "$EVID/declared-window.md" <<MD
# Pre-declared comparison window

Written BEFORE either mode ran, so the result cannot be re-rolled until it
flatters the engine.

- declared at: $WINDOW_START
- starting block: $BLOCK_START
- cycles per mode: $CYCLES
- order: baseline first, then engine
- both modes read the same live venue on chain 1952
- neither mode submits transactions in this comparison, so the book each mode sees
  is not perturbed by the other
MD
cat "$EVID/declared-window.md"

cd "$REPO"
cargo build --release -p runtime 2>&1 | tail -1

echo
echo "=== BASELINE mode ==="
ASML_REPO="$REPO" ./target/release/asml baseline "$CYCLES" | tee "$EVID/baseline-run.txt"

echo
echo "=== ENGINE mode (observe, no submissions) ==="
ASML_REPO="$REPO" ./target/release/asml observe "$CYCLES" | tee "$EVID/engine-run.txt"

echo
echo "=== comparison from the journal ==="
BLOCK_FLOOR="$BLOCK_START" python3 - <<'PY' | tee "$REPO/evidence/baseline-comparison/comparison.md"
import json, os
repo = os.environ.get('ASML_REPO', '.')
floor = int(os.environ['BLOCK_FLOOR'])
all_lines = [json.loads(l) for l in open(repo + '/evidence/journal.jsonl') if l.strip()]

# Restrict to the declared window. The first version of this script compared every
# journal entry ever written, which silently folded 15 earlier cycles into the
# "engine" column and inflated its variety. Filtering on the pre-declared starting
# block is the whole point of declaring it.
lines = [e for e in all_lines if e['block_number'] >= floor]
print(f"<!-- {len(all_lines)} journal entries total, {len(lines)} inside the declared window from block {floor} -->")
print()

baseline = [e for e in lines if 'baseline' in e['thesis']]
engine   = [e for e in lines if 'baseline' not in e['thesis']]

def summarise(rows, label):
    acted = [r for r in rows if r['action']]
    cands = [len(r['candidates']) for r in rows]
    refused = [r for r in rows if 'refused by risk' in r['risk_verdict'] and not r['risk_verdict'].startswith('approved, 0')]
    print(f"## {label}")
    print()
    print(f"- cycles recorded: {len(rows)}")
    print(f"- cycles with an action: {len(acted)}")
    print(f"- candidates evaluated per cycle: min {min(cands) if cands else 0}, max {max(cands) if cands else 0}")
    print(f"- signals consulted per cycle: {len(rows[-1]['signals']) if rows else 0}")
    print(f"- distinct actions chosen: {len(set(r['action'] for r in acted))}")
    print()

print("# Engine versus naive baseline")
print()
print("Window declared in declared-window.md before either run. Same venue, same")
print("chain, same period.")
print()
summarise(baseline, "Naive baseline")
summarise(engine, "AI decision engine")

print("## What the numbers actually show")
print()
be = set(r['action'] for r in baseline if r['action'])
ee = set(r['action'] for r in engine if r['action'])
print(f"- baseline chose {len(be)} distinct action(s): {sorted(be)}")
print(f"- engine chose {len(ee)} distinct action(s): {sorted(ee)}")
print()
if len(ee) > len(be):
    print("The engine varied its action with book state. The baseline did not, by")
    print("construction: it takes the first live order at a fixed size regardless of")
    print("spread, imbalance, or volatility.")
else:
    print("The engine did NOT vary its action more than the baseline in this window.")
    print("Reported as observed rather than adjusted.")
print()
print("## Honest limitations of this comparison")
print()
print("- No realized PnL. Neither mode's fills are marked to a later price, so this")
print("  compares decision behaviour and risk posture, not profitability. Claiming a")
print("  profit edge from this data would be unsupported.")
print("- Small sample. Four cycles per mode. Enough to show the engine responds to")
print("  state and the baseline does not, nowhere near enough for a performance claim.")
print("- The venue is self-deployed and thinly populated, so adverse selection, the")
print("  main real cost of taking liquidity, is not represented.")
PY

echo
echo "written: $EVID/"
