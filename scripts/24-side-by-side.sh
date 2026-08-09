#!/usr/bin/env bash
# Task 5.3.4: the side-by-side. Same order, same live signals, crypto market versus
# RWA-linked market, shown in a healthy state and then in a refusing state.
#
# This is the screen that decides the AI-RWA claim, so it is run twice: once with the
# instrument healthy, where BOTH markets should permit, and once with a real RWA
# condition active, where only the RWA market refuses. Showing only the second half
# would prove a global brake rather than instrument-specific intelligence.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$PATH"

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
VAULT=$(python3 -c "import json;print(json.load(open('$J'))['rwaVault'])")
RGUARD=$(python3 -c "import json;print(json.load(open('$J'))['rwaRiskGuard'])")
EVID="$REPO/evidence/rwa-live"
mkdir -p "$EVID"
OUT="$EVID/side-by-side.txt"

send() { cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo FAIL; }

cd "$REPO"
cargo build --release -p runtime 2>&1 | tail -1

{
echo "Side-by-side: crypto market versus RWA-linked market"
echo "Captured $(date -u '+%Y-%m-%d %H:%M:%S UTC'), chain 1952"
echo

echo "############ CASE 1: instrument HEALTHY ############"
echo "Expectation: both markets permit. An RWA market with a fresh oracle, no pause,"
echo "no divergence and no window nearby SHOULD behave like any other market."
echo
echo -n "setup: touchOracle -> "; send "$VAULT" "touchOracle()"
echo -n "setup: observeMarketPrice(1.00e18) -> "; send "$RGUARD" "observeMarketPrice(uint256)" 1000000000000000000
echo -n "setup: setPaused(false) -> "; send "$VAULT" "setPaused(bool)" false
echo -n "setup: setWindowSchedule(0,0) -> "; send "$VAULT" "setWindowSchedule(uint256,uint256)" 0 0
echo -n "setup: setRwaPolicy(3600,43200,300) -> "; send "$RGUARD" "setRwaPolicy(uint256,uint256,uint256)" 3600 43200 300
echo
ASML_REPO="$REPO" ./target/release/asml sidebyside
echo

echo "############ CASE 2: issuer PAUSES the instrument ############"
echo "Expectation: the crypto market is unaffected; the RWA market refuses, naming"
echo "the issuer pause. Nothing about the crypto book changed."
echo
echo -n "trigger: setPaused(true) -> "; send "$VAULT" "setPaused(bool)" true
echo
ASML_REPO="$REPO" ./target/release/asml sidebyside
echo

echo "############ CASE 3: oracle and market DIVERGE ############"
echo "Expectation: crypto unaffected; RWA refuses on divergence rather than on pause,"
echo "so the refusal tracks the actual cause."
echo
echo -n "trigger: setPaused(false) -> "; send "$VAULT" "setPaused(bool)" false
echo -n "trigger: observeMarketPrice(1.12e18) = 1200 bps -> "; send "$RGUARD" "observeMarketPrice(uint256)" 1120000000000000000
echo
ASML_REPO="$REPO" ./target/release/asml sidebyside
echo

echo "############ restore ############"
echo -n "restore: observeMarketPrice(1.00e18) -> "; send "$RGUARD" "observeMarketPrice(uint256)" 1000000000000000000
echo -n "restore: touchOracle -> "; send "$VAULT" "touchOracle()"
echo
ASML_REPO="$REPO" ./target/release/asml sidebyside
} 2>&1 | tee "$OUT"

echo
echo "written: $OUT"
