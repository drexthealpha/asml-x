#!/usr/bin/env bash
# Task 5.2.3: mutation gate for the RWA layer, both halves.
# Onchain: RwaRiskGuard and RwaVault. Offchain: the Rust rwa_check.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.foundry/bin:$HOME/.cargo/bin:$PATH"

OUT="$REPO/evidence/mutation-rwa.md"
{
  echo "# Mutation gate: the RWA layer"
  echo
  echo "Task 5.2.3, standing rule R7. Captured $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
  echo
  echo "| # | layer | mutation | result |"
  echo "|---|---|---|---|"
} > "$OUT"

N=0; PASS=0; FAIL=0

# ---------------- onchain ----------------
cd "$REPO/contracts"
G="src/RwaRiskGuard.sol"; V="src/RwaVault.sol"
GB="$HOME/.asml-mut-rwaguard.sol"; VB="$HOME/.asml-mut-rwavault.sol"
cp "$G" "$GB"; cp "$V" "$VB"
GA="$REPO/contracts/$G"; VA="$REPO/contracts/$V"
RA="$REPO/crates/risk-engine/src/lib.rs"
RB="$HOME/.asml-mut-riskengine-rwa.rs"
restore_sol() { cp "$GB" "$GA"; cp "$VB" "$VA"; }
# Absolute paths in the trap: the first version used relative ones and failed at exit
# because the working directory had moved on.
trap 'cp "$GB" "$GA" 2>/dev/null; cp "$VB" "$VA" 2>/dev/null; [ -f "$RB" ] && cp "$RB" "$RA" 2>/dev/null; true' EXIT

sol_ok() { forge test >/dev/null 2>&1; }

echo "=== onchain baseline ==="
sol_ok && echo GREEN || { echo "BASELINE RED, abort"; exit 1; }

mut_sol() { # label file sed sentinel
  N=$((N+1)); restore_sol
  sed -i "$3" "$2"
  if ! grep -qF "$4" "$2"; then
    echo "  [$1] sed did not apply"; printf '| %s | onchain | %s | sed did not apply |\n' "$N" "$1" >> "$OUT"; FAIL=$((FAIL+1)); restore_sol; return
  fi
  if sol_ok; then
    echo "  [$1] STAYED GREEN  <-- gap"; printf '| %s | onchain | %s | **STAYED GREEN, GAP** |\n' "$N" "$1" >> "$OUT"; FAIL=$((FAIL+1))
  else
    echo "  [$1] RED (good)"; printf '| %s | onchain | %s | RED, test holds |\n' "$N" "$1" >> "$OUT"; PASS=$((PASS+1))
  fi
  restore_sol
}

echo "=== onchain mutations ==="
mut_sol "pause refusal neutralised" "$G" \
  '0,/if (isPaused) {/{s|if (isPaused) {|if (false \&\& isPaused) {|}' 'if (false && isPaused) {'
mut_sol "oracle staleness refusal neutralised" "$G" \
  's|if (age > maxOracleAge) {|if (false \&\& age > maxOracleAge) {|' 'if (false && age > maxOracleAge) {'
mut_sol "window buffer refusal neutralised" "$G" \
  's|if (untilWindow > 0 \&\& untilWindow <= windowBufferSeconds) {|if (false) {|' 'if (false) {'
mut_sol "divergence refusal neutralised" "$G" \
  's|if (div > maxDivergenceBps) {|if (false \&\& div > maxDivergenceBps) {|' 'if (false && div > maxDivergenceBps) {'
mut_sol "reduce gains an RWA block (breaks the asymmetry)" "$G" \
  's|function reduceExposure(bytes32 market, uint256 amount) external override onlyAgent {|function reduceExposure(bytes32 market, uint256 amount) external override onlyAgent { require(!vault.paused(), "blocked");|' \
  'require(!vault.paused(), "blocked");'
# Single-line patterns only. The two multi-line seds in the first version silently
# failed to apply and were reported as inconclusive, which is a mutation that proves
# nothing rather than a mutation that passed.
mut_sol "setRwaPolicy loses onlyOwner" "$G" \
  's|^    ) external onlyOwner {$|    ) external {|' '    ) external {'
mut_sol "divergence made one-sided" "$G" \
  's|uint256 diff = observedMarketPrice > oracle|uint256 diff = observedMarketPrice < oracle|' \
  'uint256 diff = observedMarketPrice < oracle'
mut_sol "yield index allowed to decrease" "$V" \
  's|if (newIndex < yieldIndex) revert YieldCannotDecrease(yieldIndex, newIndex);||' \
  'yieldIndex = newIndex;'
mut_sol "oracle timestamp not refreshed on price set" "$V" \
  '/function setOraclePrice/,/^    }$/{s|oracleUpdatedAt = block.timestamp;|// MUT_NO_TIMESTAMP|}' \
  'MUT_NO_TIMESTAMP'
mut_sol "onlyIssuer removed from setPaused" "$V" \
  's|function setPaused(bool p) external onlyIssuer {|function setPaused(bool p) external {|' \
  'function setPaused(bool p) external {'

restore_sol
sol_ok && echo "onchain restored GREEN" || { echo "RESTORE RED"; exit 1; }

# ---------------- offchain ----------------
cd "$REPO"
R="$RA"
cp "$R" "$RB"
restore_rs() { cp "$RB" "$R"; }

rs_ok() { cargo test -p risk-engine --quiet >/dev/null 2>&1; }

echo
echo "=== offchain baseline ==="
rs_ok && echo GREEN || { echo "BASELINE RED, abort"; exit 1; }

mut_rs() { # label sed sentinel
  N=$((N+1)); restore_rs
  sed -i "$2" "$R"
  if ! grep -qF "$3" "$R"; then
    echo "  [$1] sed did not apply"; printf '| %s | offchain | %s | sed did not apply |\n' "$N" "$1" >> "$OUT"; FAIL=$((FAIL+1)); restore_rs; return
  fi
  if rs_ok; then
    echo "  [$1] STAYED GREEN  <-- gap"; printf '| %s | offchain | %s | **STAYED GREEN, GAP** |\n' "$N" "$1" >> "$OUT"; FAIL=$((FAIL+1))
  else
    echo "  [$1] RED (good)"; printf '| %s | offchain | %s | RED, test holds |\n' "$N" "$1" >> "$OUT"; PASS=$((PASS+1))
  fi
  restore_rs
}

echo "=== offchain mutations ==="
mut_rs "missing RWA state defaults to healthy instead of failing closed" \
  's|return Some(Refusal::RwaStateUnavailable);|return None;|' 'return None;'
mut_rs "pause refusal removed" \
  's|if rwa.issuer_paused {|if false {|' 'if false {'
mut_rs "oracle staleness comparison inverted" \
  's|if rwa.oracle_age_secs > p.max_oracle_age_secs {|if rwa.oracle_age_secs < p.max_oracle_age_secs {|' \
  'rwa.oracle_age_secs < p.max_oracle_age_secs'
mut_rs "window buffer drops the untilWindow > 0 guard" \
  's|if rwa.seconds_until_window > 0 \&\& rwa.seconds_until_window <= p.window_buffer_secs {|if rwa.seconds_until_window <= p.window_buffer_secs {|' \
  'if rwa.seconds_until_window <= p.window_buffer_secs {'
mut_rs "divergence comparison inverted" \
  's|if rwa.divergence_bps > p.max_divergence_bps {|if rwa.divergence_bps < p.max_divergence_bps {|' \
  'rwa.divergence_bps < p.max_divergence_bps'
mut_rs "RWA checks applied to every instrument kind, not just RWA" \
  's|if intent.kind != InstrumentKind::RwaLinked {|if false {|' 'if false {'
mut_rs "reduce exemption removed, so exits get blocked" \
  's|if !is_reducing {|if true {|' 'if true {'
mut_rs "is_reducing always true, so RWA checks never run" \
  's|let is_reducing = current_market_exposure != 0|let is_reducing = true \&\& current_market_exposure == current_market_exposure \&\& true; let _unused = current_market_exposure != 0|' \
  'let is_reducing = true &&'

restore_rs
rs_ok && echo "offchain restored GREEN" || { echo "RESTORE RED"; exit 1; }

{ echo; echo "## Summary"; echo; echo "- RED (good): $PASS"; echo "- gaps or inconclusive: $FAIL"; } >> "$OUT"
echo
echo "RED (good): $PASS   gaps: $FAIL"
echo "written: $OUT"
