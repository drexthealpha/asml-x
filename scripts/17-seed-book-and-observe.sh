#!/usr/bin/env bash
# Task 4.1/4.2 live proof: seed a real two-sided book on chain 1952, then run the
# Rust runtime in observe mode so it reads real state, computes real signals, and
# produces a real scored candidate set. No transactions from the agent yet.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$PATH"

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
BASE=$(python3 -c "import json;print(json.load(open('$J'))['tBASE'])")
QUOTE=$(python3 -c "import json;print(json.load(open('$J'))['tQUOTE'])")
VENUE=$(python3 -c "import json;print(json.load(open('$J'))['venue'])")

send() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['status'])" 2>/dev/null || echo FAIL
}

echo "=== seeding a two-sided book ==="
echo "existing orderCount: $(cast call "$VENUE" "orderCount()(uint256)" --rpc-url "$RPC")"

# Asks: maker sells base. Bids: maker buys base, escrowing quote.
echo -n "  ask 3 tBASE @ 2.10: "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" false 3000000000000000000 2100000000000000000
echo -n "  ask 2 tBASE @ 2.20: "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" false 2000000000000000000 2200000000000000000
echo -n "  bid 3 tBASE @ 1.90: "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" true  3000000000000000000 1900000000000000000
echo -n "  bid 2 tBASE @ 1.80: "; send "$VENUE" "postOrder(address,address,bool,uint256,uint256)" "$BASE" "$QUOTE" true  2000000000000000000 1800000000000000000

echo "new orderCount: $(cast call "$VENUE" "orderCount()(uint256)" --rpc-url "$RPC")"

echo
echo "=== building the runtime ==="
cd "$REPO"
cargo build --release -p runtime 2>&1 | tail -3

echo
echo "=== running: asml observe 4 (live chain reads, no transactions) ==="
ASML_REPO="$REPO" ./target/release/asml observe 4
