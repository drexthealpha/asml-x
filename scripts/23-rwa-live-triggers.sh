#!/usr/bin/env bash
# Task 5.2.4: prove every RWA refusal LIVE on chain 1952 by manufacturing the real
# trigger condition, not by asserting it in a test.
#
# Each step reads the guard's own view, attempts the action, and records whether the
# chain accepted or refused. Nothing here is mocked.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
VAULT=$(python3 -c "import json;print(json.load(open('$J'))['rwaVault'])")
RGUARD=$(python3 -c "import json;print(json.load(open('$J'))['rwaRiskGuard'])")
MARKET=$(python3 -c "import json;print(json.load(open('$J'))['rwaMarketId'])")
EVID="$REPO/evidence/rwa-live"
mkdir -p "$EVID"

send() { cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['status'], d['transactionHash'])" 2>/dev/null || echo "FAILED -"; }
q() { cast call "$1" "$2" "${@:3}" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}'; }

# Attempts addExposure and reports ACCEPTED or REFUSED plus the revert selector name.
try_add() {
  set +e
  OUT=$(cast send "$RGUARD" "addExposure(bytes32,uint256)" "$MARKET" "$1" \
    --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" 2>&1)
  RC=$?
  set -e
  if [ $RC -eq 0 ]; then
    echo "ACCEPTED"
  else
    REASON=$(printf '%s' "$OUT" | grep -oiE 'OracleStale|IssuerPaused|RedemptionWindowTooClose|OracleMarketDivergence|MarketCapExceeded|IsKilled' | head -1)
    echo "REFUSED(${REASON:-unknown})"
  fi
}

state() {
  printf 'tradeable=%s age=%s paused=%s untilWindow=%s divergence=%s exposure=%s\n' \
    "$(q "$RGUARD" 'rwaTradeableFlag()(bool)')" \
    "$(q "$VAULT" 'oracleAge()(uint256)')" \
    "$(q "$VAULT" 'paused()(bool)')" \
    "$(q "$VAULT" 'secondsUntilWindow()(uint256)')" \
    "$(q "$RGUARD" 'divergenceBps()(uint256)')" \
    "$(q "$RGUARD" 'exposureOf(bytes32)(uint256)' "$MARKET")"
}

LOG="$EVID/live-triggers.txt"
: > "$LOG"
log() { echo "$*" | tee -a "$LOG"; }

log "RWA live trigger proofs, chain 1952, $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
log "vault $VAULT"
log "guard $RGUARD"
log ""

log "--- A. healthy instrument: exposure should be ACCEPTED ---"
send "$VAULT" "touchOracle()" > /dev/null
log "  state: $(state)"
log "  add 5e18 -> $(try_add 5000000000000000000)"
log "  state: $(state)"
log ""

log "--- B. ISSUER PAUSE: exposure should be REFUSED ---"
log "  setPaused(true): $(send "$VAULT" "setPaused(bool)" true)"
log "  state: $(state)"
log "  add 1e18 -> $(try_add 1000000000000000000)"
log ""

log "--- C. DE-RISK WHILE PAUSED: must still be ACCEPTED (the asymmetry) ---"
log "  reduceExposure 1e18: $(send "$RGUARD" "reduceExposure(bytes32,uint256)" "$MARKET" 1000000000000000000)"
log "  state: $(state)"
log ""

log "--- D. unpause, then ORACLE DIVERGENCE: should be REFUSED ---"
log "  setPaused(false): $(send "$VAULT" "setPaused(bool)" false)"
log "  observeMarketPrice(1.10e18) against oracle 1.00e18 = 1000 bps: $(send "$RGUARD" "observeMarketPrice(uint256)" 1100000000000000000)"
log "  state: $(state)"
log "  add 1e18 -> $(try_add 1000000000000000000)"
log ""

log "--- E. divergence back inside tolerance: should be ACCEPTED ---"
log "  observeMarketPrice(1.02e18) = 200 bps: $(send "$RGUARD" "observeMarketPrice(uint256)" 1020000000000000000)"
log "  state: $(state)"
log "  add 1e18 -> $(try_add 1000000000000000000)"
log ""

log "--- F. STALE ORACLE: tighten maxOracleAge to 1s, wait, should be REFUSED ---"
log "  (threshold tightened rather than waiting an hour; the staleness itself is real)"
log "  setRwaPolicy(maxOracleAge=1, buffer=43200, maxDiv=300): $(send "$RGUARD" "setRwaPolicy(uint256,uint256,uint256)" 1 43200 300)"
sleep 8
log "  state after 8s: $(state)"
log "  add 1e18 -> $(try_add 1000000000000000000)"
log "  touchOracle to refresh: $(send "$VAULT" "touchOracle()")"
log "  state: $(state)"
log "  add 1e18 immediately after refresh -> $(try_add 1000000000000000000)"
log ""

log "--- G. REDEMPTION WINDOW PROXIMITY ---"
log "  setWindowSchedule(period=120s, length=20s): $(send "$VAULT" "setWindowSchedule(uint256,uint256)" 120 20)"
log "  setRwaPolicy(maxOracleAge=3600, buffer=100s, maxDiv=300): $(send "$RGUARD" "setRwaPolicy(uint256,uint256,uint256)" 3600 100 300)"
log "  state: $(state)"
UNTIL=$(q "$VAULT" 'secondsUntilWindow()(uint256)')
log "  secondsUntilWindow=$UNTIL, buffer=100"
log "  add 1e18 -> $(try_add 1000000000000000000)"
log "  note: when untilWindow is 0 a window is OPEN and trading is permitted, which is"
log "  the correct behaviour, not a missed refusal."
log ""

log "--- H. restore a sane policy and confirm the instrument trades again ---"
log "  setWindowSchedule(0,0): $(send "$VAULT" "setWindowSchedule(uint256,uint256)" 0 0)"
log "  setRwaPolicy(3600,43200,300): $(send "$RGUARD" "setRwaPolicy(uint256,uint256,uint256)" 3600 43200 300)"
log "  touchOracle: $(send "$VAULT" "touchOracle()")"
log "  state: $(state)"
log "  add 1e18 -> $(try_add 1000000000000000000)"
log ""
log "  gross=$(q "$RGUARD" 'gross()(uint256)') sumOfParts=$(q "$RGUARD" 'sumOfParts()(uint256)')"

echo
echo "written: $LOG"
