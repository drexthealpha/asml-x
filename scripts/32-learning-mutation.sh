#!/usr/bin/env bash
# Phase 7 mutation gate (R7). Break each learning guarantee, confirm RED, restore.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$PATH"

L="$REPO/crates/learning/src/lib.rs"
D="$REPO/crates/decision-engine/src/lib.rs"
LB="$HOME/.asml-mut-learning.rs"
DB="$HOME/.asml-mut-decision.rs"
cp "$L" "$LB"; cp "$D" "$DB"
trap 'cp "$LB" "$L" 2>/dev/null; cp "$DB" "$D" 2>/dev/null; true' EXIT
restore() { cp "$LB" "$L"; cp "$DB" "$D"; }

OUT="$REPO/evidence/mutation-learning.md"
{
  echo "# Mutation gate: the learning layer"
  echo
  echo "Phase 7, standing rule R7. Captured $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
  echo
  echo "| # | file | mutation | result |"
  echo "|---|---|---|---|"
} > "$OUT"

N=0; PASS=0; FAIL=0
ok() { cd "$REPO"; cargo test -p learning --quiet >/dev/null 2>&1; }

echo "=== baseline ==="
ok && echo GREEN || { echo "BASELINE RED, abort"; exit 1; }

mut() { # label file sed sentinel
  N=$((N+1)); restore
  sed -i "$3" "$2"
  if ! grep -qF "$4" "$2"; then
    echo "  [$1] sed did not apply"
    printf '| %s | %s | %s | sed did not apply |\n' "$N" "$(basename "$2")" "$1" >> "$OUT"
    FAIL=$((FAIL+1)); restore; return
  fi
  if ok; then
    echo "  [$1] STAYED GREEN  <-- gap"
    printf '| %s | %s | %s | **STAYED GREEN, GAP** |\n' "$N" "$(basename "$2")" "$1" >> "$OUT"
    FAIL=$((FAIL+1))
  else
    echo "  [$1] RED (good)"
    printf '| %s | %s | %s | RED, test holds |\n' "$N" "$(basename "$2")" "$1" >> "$OUT"
    PASS=$((PASS+1))
  fi
  restore
}

echo "=== mutations ==="

# The single most important one: sever the learned parameter from the decision. If this
# stays GREEN, the parameter is decorative and the whole phase is theatre.
mut "momentum weight severed from the decision (parameter never read)" "$D" \
  's|let expected_move = self.expected_move_bps(signals);|let expected_move = 0; let _ = self.expected_move_bps(signals);|' \
  'let expected_move = 0;'

mut "dead band removed, so a flat market scores every forecast wrong" "$L" \
  's|if realized_move_bps.abs() < DEAD_BAND_BPS {|if false {|' 'if false {'

mut "dead band made enormous, so nothing is ever scored" "$L" \
  's|pub const DEAD_BAND_BPS: i128 = 5;|pub const DEAD_BAND_BPS: i128 = 1000000;|' \
  'DEAD_BAND_BPS: i128 = 1000000'

mut "settle lag ignored, so a forecast is scored against its own price" "$L" \
  's|if now_ms.saturating_sub(p.opened_at_ms) < lag_ms |if false \&\& now_ms.saturating_sub(p.opened_at_ms) < lag_ms |' \
  'if false && now_ms.saturating_sub'

mut "direction scoring inverted" "$L" \
  's|Predicted::Up => realized_move_bps > 0,|Predicted::Up => realized_move_bps < 0,|' \
  'Predicted::Up => realized_move_bps < 0,'

mut "minimum sample guard removed, learning from noise" "$L" \
  's|if stats.samples < MIN_SAMPLES_TO_UPDATE {|if false {|' 'if false {'

mut "momentum weight upper clamp removed" "$L" \
  's|let new = proposed.clamp(i64::from(MOMENTUM_WEIGHT_MIN), i64::from(MOMENTUM_WEIGHT_MAX));|let new = proposed.max(i64::from(MOMENTUM_WEIGHT_MIN));|' \
  'let new = proposed.max(i64::from(MOMENTUM_WEIGHT_MIN));'

mut "weight update sign inverted, so a good signal loses weight" "$L" \
  's|let edge_from_coinflip = hit - 5_000;|let edge_from_coinflip = 5_000 - hit;|' \
  'let edge_from_coinflip = 5_000 - hit;'

# Single-line patterns only. The two multi-line seds in the first version silently failed
# to apply, and a mutation that does not apply proves nothing at all.
mut "holds are scored instead of dropped" "$L" \
  's|== Predicted::NoView {|== Predicted::NoView \&\& false {|' \
  '== Predicted::NoView && false {'

mut "pending forecasts no longer persisted" "$L" \
  's|"pending": pending,|"pending": Vec::<Value>::new(),|' '"pending": Vec::<Value>::new(),'

mut "learned params no longer persisted" "$L" \
  's|"momentum_weight_bps": self.params.momentum_weight_bps,|"momentum_weight_bps": 2000,|' \
  '"momentum_weight_bps": 2000,'

mut "param change loses its sample-count attribution" "$L" \
  's|samples: stats.samples,|samples: 0,|' 'samples: 0,'

restore
ok && echo "restored GREEN" || { echo "RESTORE RED"; exit 1; }

{ echo; echo "## Summary"; echo; echo "- RED (good): $PASS"; echo "- gaps or inconclusive: $FAIL"; } >> "$OUT"
echo
echo "RED (good): $PASS   gaps: $FAIL"
echo "written: $OUT"
