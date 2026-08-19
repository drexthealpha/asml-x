#!/usr/bin/env bash
# Deploy the RWA stack to X LAYER MAINNET, chain 196.
#
# WHY THIS MATTERS MORE THAN ITS SIZE. The RWA refusal layer is this project's differentiator and the
# hackathon runs a separate AI-RWA track. `deployments-mainnet.json` held venue, riskGuard,
# batchExecutor and agentVault, and no RWA contracts at all, so a judge checking mainnet for that
# track would find the core product live and the RWA angle absent. Two contracts, already written,
# already tested, already formally verified on testnet. There was no reason for them to be missing.
#
# COSTS REAL OKB, from the deployer the user funded. The whole Phase 12 launch cost 0.000203652 OKB,
# so two more contracts are the same order of magnitude.
#
# EVIDENCE PATH: evidence/phase19/rwa-mainnet.md
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

RPC="$XLAYER_MAINNET_RPC"
CHAIN_ID="$XLAYER_MAINNET_CHAIN_ID"
M="$REPO/deployments-mainnet.json"
OUT="$REPO/evidence/phase19/rwa-mainnet.md"
mkdir -p "$(dirname "$OUT")"
cd "$REPO/contracts"

CAST="$HOME/.foundry/bin/cast"
FORGE="$HOME/.foundry/bin/forge"
PASS="$(keystore_pass)"

# Refuse to run against anything but mainnet. The runtime has this guard for the same reason: a
# deploy that silently lands on the wrong chain is worse than one that fails.
LIVE=$("$CAST" chain-id --rpc-url "$RPC")
if [ "$LIVE" != "$CHAIN_ID" ]; then
  echo "expected chain $CHAIN_ID, got $LIVE. Refusing."
  exit 1
fi
echo "chain $LIVE confirmed"
echo "deployer $DEPLOYER_ADDRESS"
echo "balance  $("$CAST" balance --ether "$DEPLOYER_ADDRESS" --rpc-url "$RPC") OKB"
echo

dep() {
  "$FORGE" create "$1" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" \
    --broadcast --json "${@:2}" 2>/dev/null | grep -oE '0x[0-9a-fA-F]{40}' | sed -n 2p
}
send() {
  "$CAST" send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo FAIL
}

echo "=== RwaVault: price 1.0, window period 0 ==="
VAULT=$(dep src/RwaVault.sol:RwaVault --constructor-args 1000000000000000000 0 0)
echo "  RwaVault      $VAULT"

echo "=== RwaRiskGuard: gross 1000e18, oracle age 3600s, buffer 43200s, divergence 300bps ==="
RGUARD=$(dep src/RwaRiskGuard.sol:RwaRiskGuard --constructor-args \
  1000000000000000000000 "$VAULT" 3600 43200 300)
echo "  RwaRiskGuard  $RGUARD"

if [ -z "$VAULT" ] || [ -z "$RGUARD" ]; then
  echo "DEPLOY FAILED"
  exit 1
fi

RWA_MARKET=$("$CAST" keccak "RWA/tQUOTE")
echo "  marketId      $RWA_MARKET"

echo
echo "=== wiring ==="
echo -n "  setMarketCap 400e18: "; send "$RGUARD" "setMarketCap(bytes32,uint256)" "$RWA_MARKET" 400000000000000000000
echo -n "  setAgent(deployer):  "; send "$RGUARD" "setAgent(address,bool)" "$DEPLOYER_ADDRESS" true

echo
echo "=== recording in deployments-mainnet.json ==="
python3 - "$M" "$VAULT" "$RGUARD" "$RWA_MARKET" <<'PY'
import json, sys
p, vault, guard, market = sys.argv[1:5]
d = json.load(open(p, encoding="utf-8"))
d["rwaVault"] = vault
d["rwaRiskGuard"] = guard
d["rwaMarketId"] = market
json.dump(d, open(p, "w", encoding="utf-8", newline="\n"), indent=2)
print(f"  rwaVault      {vault}")
print(f"  rwaRiskGuard  {guard}")
PY

echo
echo "=== read back FROM CHAIN, not from the file we just wrote ==="
VCODE=$("$CAST" code "$VAULT" --rpc-url "$RPC" | wc -c)
GCODE=$("$CAST" code "$RGUARD" --rpc-url "$RPC" | wc -c)
PRICE=$("$CAST" call "$VAULT" "oraclePrice()(uint256)" --rpc-url "$RPC" 2>/dev/null || echo ERR)
CAP=$("$CAST" call "$RGUARD" "maxPerMarket(bytes32)(uint256)" "$RWA_MARKET" --rpc-url "$RPC" 2>/dev/null || echo ERR)
echo "  RwaVault bytecode chars     $VCODE"
echo "  RwaRiskGuard bytecode chars $GCODE"
echo "  vault oraclePrice()               $PRICE"
echo "  guard maxPerMarket()        $CAP"

{
echo "# RWA layer on X Layer mainnet"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Chain **$LIVE**."
echo
echo "The RWA refusal layer is this project's differentiator and the hackathon runs a separate"
echo "AI-RWA track. Until this run it existed only on testnet 1952, so a judge checking mainnet for"
echo "that track would have found the core product live and the RWA angle absent."
echo
echo "| contract | address | bytecode |"
echo "|---|---|---|"
echo "| RwaVault | \`$VAULT\` | $VCODE chars |"
echo "| RwaRiskGuard | \`$RGUARD\` | $GCODE chars |"
echo
echo "Market id \`$RWA_MARKET\`."
echo
echo "## Read back from chain"
echo
echo "These are read from chain $LIVE after the deploy, not from the file this script wrote:"
echo
echo '```'
echo "vault oraclePrice()        $PRICE"
echo "guard maxPerMarket() $CAP"
echo '```'
echo
echo "## What the RWA layer adds"
echo
echo "Four refusals that only mean anything for an instrument backed by something off-chain: a stale"
echo "oracle, a paused issuer, a redemption window, and divergence between the oracle and the market."
echo "A crypto-only risk engine has no reason to check any of them."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/209-deploy-rwa-mainnet.sh"
echo '```'
} > "$OUT"

echo
echo "written: $OUT"
[ -n "$VAULT" ] && [ -n "$RGUARD" ]
