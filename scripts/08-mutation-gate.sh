#!/usr/bin/env bash
# Task 2.1.8 (R7 mutation gate) and task 2.1.4 (compile-time bypass proof).
#
# For each mutation: apply it, confirm the suite goes RED, restore, confirm GREEN.
# A mutation that stays GREEN means the limit it touches has no real test.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$PATH"
cd "$REPO"

LIB="crates/risk-engine/src/lib.rs"
BAK="$HOME/.asml-mutation-backup-lib.rs"
EVID="$REPO/evidence"
mkdir -p "$EVID"
OUT="$EVID/mutation-risk-engine.md"

cp "$LIB" "$BAK"
restore() { cp "$BAK" "$LIB"; }
trap restore EXIT

quiet_test() { cargo test --workspace --quiet >/dev/null 2>&1; }

{
  echo "# Mutation gate: risk engine"
  echo
  echo "Task 2.1.8, standing rule R7. Captured $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
  echo
  echo "Method: break the exact thing a test guards, confirm the suite goes RED,"
  echo "restore, confirm GREEN. A mutation that stays GREEN proves the limit has"
  echo "no real test, and that test is then deleted or rewritten."
  echo
  echo "| # | mutation | expected | result |"
  echo "|---|---|---|---|"
} > "$OUT"

echo "=== baseline must be GREEN before mutating ==="
if quiet_test; then echo "baseline GREEN"; else echo "BASELINE RED, aborting"; exit 1; fi

PASS=0
FAIL=0

mutate() {
  # $1 = label, $2 = sed expression
  restore
  sed -i "$2" "$LIB"
  if grep -qF "$3" "$LIB"; then
    if quiet_test; then
      echo "  [$1] STAYED GREEN  <-- test gap"
      printf '| %s | %s | RED | **STAYED GREEN, TEST GAP** |\n' "$((PASS+FAIL+1))" "$1" >> "$OUT"
      FAIL=$((FAIL+1))
    else
      echo "  [$1] went RED (good)"
      printf '| %s | %s | RED | RED, test holds |\n' "$((PASS+FAIL+1))" "$1" >> "$OUT"
      PASS=$((PASS+1))
    fi
  else
    echo "  [$1] SED DID NOT APPLY, skipping"
    printf '| %s | %s | RED | sed did not apply, inconclusive |\n' "$((PASS+FAIL+1))" "$1" >> "$OUT"
    FAIL=$((FAIL+1))
  fi
  restore
}

echo
echo "=== mutations ==="

mutate "order notional: > becomes >=" \
  's|if order_notional > self.limits.max_order_notional_micro|if order_notional >= self.limits.max_order_notional_micro|' \
  'order_notional >= self.limits.max_order_notional_micro'

mutate "order notional: invert to <" \
  's|if order_notional > self.limits.max_order_notional_micro|if order_notional < self.limits.max_order_notional_micro|' \
  'order_notional < self.limits.max_order_notional_micro'

mutate "market notional: invert" \
  's|if projected_market > self.limits.max_market_notional_micro|if projected_market < self.limits.max_market_notional_micro|' \
  'projected_market < self.limits.max_market_notional_micro'

mutate "gross notional: invert" \
  's|if projected_gross > self.limits.max_gross_notional_micro|if projected_gross < self.limits.max_gross_notional_micro|' \
  'projected_gross < self.limits.max_gross_notional_micro'

mutate "net skew: invert" \
  's|if projected_net > self.limits.max_net_skew_micro|if projected_net < self.limits.max_net_skew_micro|' \
  'projected_net < self.limits.max_net_skew_micro'

mutate "free margin: invert" \
  's|if would_leave < self.limits.min_free_margin_micro|if would_leave > self.limits.min_free_margin_micro|' \
  'would_leave > self.limits.min_free_margin_micro'

mutate "mark staleness: invert" \
  's|if age > self.limits.max_mark_age_ms|if age < self.limits.max_mark_age_ms|' \
  'age < self.limits.max_mark_age_ms'

mutate "rate limit: invert" \
  's|if ctx.actions_last_minute >= self.limits.max_actions_per_minute|if ctx.actions_last_minute <= self.limits.max_actions_per_minute|' \
  'ctx.actions_last_minute <= self.limits.max_actions_per_minute'

mutate "daily loss kill: invert comparison" \
  's|if pf.realized_pnl_today_micro <= -self.limits.daily_loss_limit_micro|if pf.realized_pnl_today_micro >= -self.limits.daily_loss_limit_micro|' \
  'pf.realized_pnl_today_micro >= -self.limits.daily_loss_limit_micro'

mutate "consecutive losses kill: invert" \
  's|if pf.consecutive_losses >= self.limits.max_consecutive_losses|if pf.consecutive_losses <= self.limits.max_consecutive_losses|' \
  'pf.consecutive_losses <= self.limits.max_consecutive_losses'

mutate "manual kill switch: neutralise" \
  's|if ctx.manual_kill {|if false \&\& ctx.manual_kill {|' \
  'if false && ctx.manual_kill {'

mutate "data stale kill: neutralise" \
  's|if ctx.data_stale {|if false \&\& ctx.data_stale {|' \
  'if false && ctx.data_stale {'

mutate "non-positive size guard: neutralise" \
  's|if intent.size_micro <= 0 {|if intent.size_micro < i128::MIN {|' \
  'if intent.size_micro < i128::MIN {'

restore
# The notional maths lives in core-types, not in the risk engine, so this
# mutation targets a different file and needs its own backup.
CT="crates/core-types/src/lib.rs"
CTBAK="$HOME/.asml-mutation-backup-coretypes.rs"
cp "$CT" "$CTBAK"
sed -i 's|(self.size_micro \* self.limit_price_micro) / MICRO|(self.size_micro * self.limit_price_micro)|' "$CT"
if grep -qF '(self.size_micro * self.limit_price_micro)\n' "$CT" || \
   ! grep -qF '(self.size_micro * self.limit_price_micro) / MICRO' "$CT"; then
  if quiet_test; then
    echo "  [fixed-point scale: drop MICRO divisor] STAYED GREEN  <-- test gap"
    printf '| %s | fixed-point scale: drop MICRO divisor in notional | RED | **STAYED GREEN, TEST GAP** |\n' "$((PASS+FAIL+1))" >> "$OUT"
    FAIL=$((FAIL+1))
  else
    echo "  [fixed-point scale: drop MICRO divisor] went RED (good)"
    printf '| %s | fixed-point scale: drop MICRO divisor in notional | RED | RED, test holds |\n' "$((PASS+FAIL+1))" >> "$OUT"
    PASS=$((PASS+1))
  fi
else
  echo "  [fixed-point scale] SED DID NOT APPLY"
  printf '| %s | fixed-point scale: drop MICRO divisor | RED | sed did not apply |\n' "$((PASS+FAIL+1))" >> "$OUT"
  FAIL=$((FAIL+1))
fi
cp "$CTBAK" "$CT"

restore
echo
echo "=== restore verified ==="
if quiet_test; then echo "restored GREEN"; else echo "RESTORE FAILED, RED"; exit 1; fi

echo
echo "=== task 2.1.4: prove the risk gate cannot be bypassed at compile time ==="
BYPASS="crates/executor/src/bypass_probe.rs"
cat > "$BYPASS" <<'RS'
// Temporary probe. Attempts to forge a RiskApproved from outside risk-engine.
// Must NOT compile. Generated and deleted by scripts/08-mutation-gate.sh.
use core_types::{InstrumentKind, MarketId, OrderIntent, Side};
use risk_engine::RiskApproved;

pub fn forge() -> RiskApproved<OrderIntent> {
    RiskApproved {
        inner: OrderIntent {
            market: MarketId::new("FORGED"),
            kind: InstrumentKind::Spot,
            side: Side::Buy,
            size_micro: i128::MAX,
            limit_price_micro: i128::MAX,
            decision_id: 0,
        },
        requires_human_approval: false,
        approved_at_ms: 0,
        _seal: (),
    }
}
RS
echo "pub mod bypass_probe;" >> crates/executor/src/lib.rs

set +e
cargo build -p executor > "$EVID/bypass-compile-error.txt" 2>&1
BUILD_RC=$?
set -e

# Undo the probe regardless of outcome.
rm -f "$BYPASS"
sed -i '/pub mod bypass_probe;/d' crates/executor/src/lib.rs

if [ "$BUILD_RC" -ne 0 ]; then
  echo "RESULT: forging RiskApproved FAILS TO COMPILE, as required."
  grep -E '^error|private|E0451|E0063|E0560' "$EVID/bypass-compile-error.txt" | head -12
  {
    echo
    echo "## Task 2.1.4: compile-time bypass proof"
    echo
    echo "Status: DEMONSTRATED. Forging a \`RiskApproved\` from the executor crate"
    echo "fails to build. Full compiler output: evidence/bypass-compile-error.txt"
    echo
    echo '```'
    grep -E '^error|private|E0451|E0063|E0560' "$EVID/bypass-compile-error.txt" | head -12
    echo '```'
    echo
    echo "This is why the guarantee is architectural rather than procedural: an"
    echo "agent that tries to skip the risk gate does not fail a runtime check, it"
    echo "fails to compile. The workspace also forbids unsafe_code, so there is no"
    echo "transmute escape."
  } >> "$OUT"
else
  echo "RESULT: FORGERY COMPILED. The architectural guarantee is BROKEN."
  {
    echo
    echo "## Task 2.1.4: FAILED"
    echo
    echo "Forging a RiskApproved COMPILED. The guarantee does not hold. Fix before"
    echo "proceeding."
  } >> "$OUT"
fi

echo
echo "=== final state must be GREEN ==="
quiet_test && echo "GREEN" || echo "RED, investigate"

{
  echo
  echo "## Summary"
  echo
  echo "- mutations that correctly went RED: $PASS"
  echo "- mutations that stayed GREEN or were inconclusive: $FAIL"
} >> "$OUT"

echo
echo "mutations RED (good): $PASS"
echo "mutations GREEN or inconclusive: $FAIL"
echo "written: $OUT"
