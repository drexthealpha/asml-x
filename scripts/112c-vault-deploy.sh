#!/usr/bin/env bash
# Deploy AgentVault to X Layer testnet and record it in deployments.json.
#
# The trade target is the OrderBookVenue, which is where funds legitimately go when the agent acts.
# It is passed as a CONSTRUCTOR argument and stored immutable, so the agent can never be redirected
# at an attacker-chosen contract, not even by the owner. That is the property task 8.2's
# `test_thereIsNoFunctionThatMovesFundsToAnArbitraryAddress` checks in the suite; this makes it true
# of the deployed bytecode too.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
a() { python3 -c "import json;print(json.load(open('$J'))['$1'])"; }
QUOTE=$(a tQUOTE); VENUE=$(a venue)

cd "$REPO/contracts"

echo "=== deploying AgentVault(asset=$QUOTE, tradeTarget=$VENUE) ==="
VAULT=$(forge create src/AgentVault.sol:AgentVault \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --broadcast --json \
  --constructor-args "$QUOTE" "$VENUE" 2>/dev/null | grep -oE '0x[0-9a-fA-F]{40}' | sed -n 2p)

if [ -z "$VAULT" ]; then echo "DEPLOY FAILED"; exit 1; fi
echo "AgentVault     $VAULT"

send() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['status'], d['transactionHash'])" 2>/dev/null \
    || echo "SEND FAILED"
}

# The deployer acts as the agent on testnet, which is the same key the runtime signs with.
echo -n "vault.setAgent(deployer): "; send "$VAULT" "setAgent(address)" "$DEPLOYER_ADDRESS"
echo -n "approve vault for tQUOTE: "; send "$QUOTE" "approve(address,uint256)" "$VAULT" 1000000000000000000000000

# Record the deploy block so the log scanner has a floor, the same way the FeeCollector does.
BLK=$(cast block-number --rpc-url "$RPC")

echo
echo "=== read back from chain ==="
echo "vault.asset        $(cast call "$VAULT" "asset()(address)" --rpc-url "$RPC")"
echo "vault.tradeTarget  $(cast call "$VAULT" "tradeTarget()(address)" --rpc-url "$RPC")"
echo "vault.agent        $(cast call "$VAULT" "agent()(address)" --rpc-url "$RPC")"
echo "vault.owner        $(cast call "$VAULT" "owner()(address)" --rpc-url "$RPC")"
echo "vault.isSolvent    $(cast call "$VAULT" "isSolvent()(bool)" --rpc-url "$RPC")"

python3 - "$J" "$VAULT" "$BLK" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["agentVault"] = sys.argv[2]
d["agentVaultDeployBlock"] = int(sys.argv[3])
json.dump(d, open(p, "w"), indent=2)
print(f"deployments.json: agentVault {sys.argv[2]} at block {sys.argv[3]}")
PY

# Keep the human-readable deployment table and the UI manifest in step, so the dashboard cannot show
# a stale set of contracts. This is the defect Phase 7 found in three separate places.
DOCS="$REPO/docs/verified/deployments.md"
if ! grep -q "AgentVault" "$DOCS"; then
  python3 - "$DOCS" "$VAULT" <<'PY'
import sys
p, vault = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
row = f"| AgentVault | `{vault}` | user custody: agent may trade, never withdraw |\n"
i = s.index("\nMarket id")
s = s[:i] + "\n" + row.rstrip() + s[i:]
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("deployments.md: AgentVault row added")
PY
fi
python3 "$REPO/scripts/build_ui_manifest.py" | tail -3

echo "explorer: https://www.oklink.com/x-layer-testnet/address/$VAULT"
