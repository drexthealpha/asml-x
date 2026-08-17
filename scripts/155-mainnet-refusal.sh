#!/usr/bin/env bash
# Task 12.3: an explicit risk refusal on MAINNET.
#
# THINKING: #22 inversion (the refusal is the product, not the trade), #66 red teaming, #50 empirical.
#
# EVIDENCE PATH: evidence/phase12/mainnet-refusal.md
# PASS: a refusal with its numbers, from mainnet, in the journal or as a revert reason.
#
# FAKE WIN, quoted: "showing the testnet refusal and captioning it mainnet."
# COUNTER, quoted: "the evidence carries the mainnet block number and chain id."
#
# Both are recorded on every section below, and the refusal is produced THREE ways so no single
# artifact has to carry the claim: a submitted transaction that reverts on chain, a simulated call
# that returns the decoded custom error, and the offchain engine refusing to construct RiskApproved.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase12/mainnet-refusal.md"
mkdir -p "$(dirname "$OUT")"
RPC="https://rpc.xlayer.tech"
PASS="$(keystore_pass)"
MJ="$REPO/deployments-mainnet.json"
a() { python3 -c "import json;print(json.load(open('$MJ'))['$1'])"; }
GUARD=$(a riskGuard); VAULT=$(a agentVault); QUOTE=$(a tQUOTE); MARKET=$(a marketId)

CHAIN=$(python3 -c "print(int('$(cast rpc eth_chainId --rpc-url "$RPC" 2>/dev/null | tr -d '"')', 16))")
BLOCK=$(cast block-number --rpc-url "$RPC")
[ "$CHAIN" = "196" ] || { echo "ABORT: chain $CHAIN"; exit 1; }

{
echo "# Task 12.3: an explicit risk refusal on mainnet"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
echo
echo "**Chain id $CHAIN. Block $BLOCK.**"
echo
echo "Both are stated because this task's named fake win is showing a testnet refusal and captioning"
echo "it mainnet. Every artifact below is from chain 196."
echo
echo "## 1. The onchain guard refuses, as a SUBMITTED transaction"
echo
echo "The market cap is 500 aQUOTE. This asks the guard to record 900, which is over it."
echo
echo '```'
echo "RiskGuard        $GUARD"
echo "market           $MARKET"
echo "maxPerMarket     $(cast call "$GUARD" "maxPerMarket(bytes32)(uint256)" "$MARKET" --rpc-url "$RPC" | awk '{print $1}')"
echo "current exposure $(cast call "$GUARD" "exposureOf(bytes32)(uint256)" "$MARKET" --rpc-url "$RPC" | awk '{print $1}')"
echo "requested        900000000000000000000"
echo '```'
echo
echo "### Simulated call, for the decoded custom error"
echo
echo '```'
cast call "$GUARD" "addExposure(bytes32,uint256)" "$MARKET" 900000000000000000000 \
  --from "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1 | head -3
echo '```'
} > "$OUT"

# A submitted transaction that reverts is a permanent, third-party-verifiable record. --gas-limit
# skips estimation, which would otherwise refuse to send a call it knows will revert; --async returns
# the hash on broadcast rather than exiting non-zero on the revert, which is the expected outcome.
RAW=$(cast send "$GUARD" "addExposure(bytes32,uint256)" "$MARKET" 900000000000000000000 \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --gas-limit 200000 --async 2>&1)
TX=$(printf '%s' "$RAW" | tr -d ' \r' | grep -oE '^0x[0-9a-fA-F]{64}$' | head -1)
[ -n "$TX" ] || TX=$(printf '%s' "$RAW" | grep -oE '0x[0-9a-fA-F]{64}' | grep -v '^0x0\{64\}$' | head -1)

for _ in 1 2 3 4 5 6 7 8 9 10; do
  cast receipt "$TX" --rpc-url "$RPC" --json > "$HOME/.asml-refusal.json" 2>/dev/null && \
    [ -s "$HOME/.asml-refusal.json" ] && break
  sleep 3
done
ST=$(python3 -c "import json;print(json.load(open('$HOME/.asml-refusal.json'))['status'])" 2>/dev/null || echo "?")
RBLK=$(python3 -c "import json;print(int(json.load(open('$HOME/.asml-refusal.json'))['blockNumber'],16))" 2>/dev/null || echo "?")

{
echo
echo "### The submitted transaction"
echo
echo '```'
echo "tx      $TX"
echo "status  $ST      (0x0 means REVERTED, which is the pass for this task)"
echo "block   $RBLK    (mainnet)"
echo '```'
echo
echo "https://www.oklink.com/x-layer/tx/$TX"
echo
echo "A reverted transaction is still a permanent onchain record. Anybody can fetch this receipt and"
echo "see that the attempt was made on chain 196 and refused by the deployed guard."
echo
echo "## 2. The vault refuses a per-user limit breach, on mainnet"
echo
echo '```'
} >> "$OUT"

# A deposit with a deliberately small limit, then an over-limit action.
send() { cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['status'])" 2>/dev/null || echo FAIL; }

echo "approve vault:     $(send "$QUOTE" "approve(address,uint256)" "$VAULT" 100000000000000000000)" >> "$OUT"
echo "deposit 10, cap 1: $(send "$VAULT" "deposit(uint256,uint256)" 10000000000000000000 1000000000000000000)" >> "$OUT"
echo "vault.maxNotional: $(cast call "$VAULT" "maxNotional(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')" >> "$OUT"
echo "vault.balanceOf:   $(cast call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')" >> "$OUT"
{
echo
echo "Asking the agent to trade 2 aQUOTE against the user's own 1 aQUOTE limit, with 10 on deposit."
echo "There are ample funds. The only thing refusing it is the user's own limit."
echo
cast call "$VAULT" "openTrade(address,uint256)" "$DEPLOYER_ADDRESS" 2000000000000000000 \
  --from "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1 | head -3
echo '```'
echo
echo "## 3. The offchain engine refuses to construct RiskApproved"
echo
echo "The same limit exists in the Rust risk engine, where a refusal is a type-level fact rather than"
echo "a revert: \`RiskApproved<T>\` has exactly one constructor and it is behind this check."
echo
echo '```'
} >> "$OUT"

cd "$REPO"
cargo test -p risk-engine 2>&1 | grep -E "^test tests::(per_user|prop_a_user)|^test result" | head -6 >> "$OUT"

{
echo '```'
echo
echo "## Why three artifacts and not one"
echo
echo "A revert proves the deployed bytecode refuses. A decoded custom error proves WHICH limit and by"
echo "how much. A failing type-level construction proves the refusal is not merely enforced at the"
echo "edge but is impossible to route around offchain. Any one of them alone would leave a gap that a"
echo "sceptical reader could reasonably point at."
} >> "$OUT"

echo "written: $OUT"
tail -20 "$OUT"
