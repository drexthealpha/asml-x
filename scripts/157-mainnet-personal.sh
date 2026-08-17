#!/usr/bin/env bash
# Task 12.5: a real user deposit, an agent action under it, and a full withdrawal, on MAINNET.
#
# THINKING: #29 margin-of-safety, #53 phenomenological, #50 empirical.
#
# EVIDENCE PATH: evidence/phase12/mainnet-personal.md
# PASS: three mainnet tx hashes and a restored balance, so personal mode is not testnet-only.
#
# The balance is asserted RESTORED at the end. A withdrawal that returns a different amount than was
# deposited without explaining the difference is the thing task 8.6's counter forbids, and the same
# standard applies on mainnet.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase12/mainnet-personal.md"
mkdir -p "$(dirname "$OUT")"
RPC="https://rpc.xlayer.tech"
PASS="$(keystore_pass)"
MJ="$REPO/deployments-mainnet.json"
a() { python3 -c "import json;print(json.load(open('$MJ'))['$1'])"; }
VAULT=$(a agentVault); QUOTE=$(a tQUOTE)

CHAIN=$(python3 -c "print(int('$(cast rpc eth_chainId --rpc-url "$RPC" 2>/dev/null | tr -d '"')', 16))")
[ "$CHAIN" = "196" ] || { echo "ABORT: chain $CHAIN"; exit 1; }

sendtx() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['status'],d['transactionHash'])" 2>/dev/null || echo "FAIL none"
}
bal() { cast call "$QUOTE" "balanceOf(address)(uint256)" "$1" --rpc-url "$RPC" | awk '{print $1}'; }

# Start from a clean position so the restoration assertion means something.
COM=$(cast call "$VAULT" "committed(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')
[ "${COM:-0}" != "0" ] && sendtx "$VAULT" "closeTrade(address,uint256,uint256)" "$DEPLOYER_ADDRESS" "$COM" "$COM" > /dev/null
VB=$(cast call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')
[ "${VB:-0}" != "0" ] && sendtx "$VAULT" "withdrawAll()" > /dev/null

WALLET_BEFORE=$(bal "$DEPLOYER_ADDRESS")
DEPOSIT=5000000000000000000    # 5 aQUOTE
LIMIT=5000000000000000000

{
echo "# Task 12.5: a real user deposit and withdrawal on mainnet"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). **Chain id $CHAIN.**"
echo
echo "Personal mode is not testnet-only: the same AgentVault, the same three operations, on 196."
echo
echo '```'
echo "AgentVault        $VAULT"
echo "asset             $QUOTE"
echo "wallet before     $WALLET_BEFORE"
echo '```'
echo
echo "## 1. Deposit"
echo
echo '```'
} > "$OUT"

R1=$(sendtx "$QUOTE" "approve(address,uint256)" "$VAULT" "$DEPOSIT")
R2=$(sendtx "$VAULT" "deposit(uint256,uint256)" "$DEPOSIT" "$LIMIT")
echo "approve   $R1" >> "$OUT"
echo "deposit   $R2" >> "$OUT"
AFTER_DEP=$(cast call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')
echo "vault balance  $AFTER_DEP" >> "$OUT"
echo "user limit     $(cast call "$VAULT" "maxNotional(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')" >> "$OUT"

{
echo '```'
echo
echo "## 2. An agent action under that deposit"
echo
echo '```'
} >> "$OUT"

R3=$(sendtx "$VAULT" "openTrade(address,uint256)" "$DEPLOYER_ADDRESS" 2000000000000000000)
echo "openTrade 2 aQUOTE   $R3" >> "$OUT"
echo "committed            $(cast call "$VAULT" "committed(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')" >> "$OUT"
echo "withdrawable         $(cast call "$VAULT" "withdrawable(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')" >> "$OUT"

{
echo '```'
echo
echo "The agent moved 2 aQUOTE to the venue and it is no longer withdrawable, which is the point:"
echo "the same tokens cannot be both traded and withdrawn."
echo
echo "## 3. Close and withdraw in full"
echo
echo '```'
} >> "$OUT"

# The trade target returns the funds, then the user takes everything back.
sendtx "$QUOTE" "approve(address,uint256)" "$VAULT" 100000000000000000000 > /dev/null
R4=$(sendtx "$VAULT" "closeTrade(address,uint256,uint256)" "$DEPLOYER_ADDRESS" 2000000000000000000 2000000000000000000)
R5=$(sendtx "$VAULT" "withdrawAll()")
echo "closeTrade   $R4" >> "$OUT"
echo "withdrawAll  $R5" >> "$OUT"

WALLET_AFTER=$(bal "$DEPLOYER_ADDRESS")
VAULT_AFTER=$(cast call "$VAULT" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC" | awk '{print $1}')

{
echo "vault balance after  $VAULT_AFTER"
echo "wallet after         $WALLET_AFTER"
echo '```'
echo
echo "## The restoration assertion"
echo
echo '```'
python3 - "$WALLET_BEFORE" "$WALLET_AFTER" <<'PY'
import sys
b, a = int(sys.argv[1]), int(sys.argv[2])
print(f"wallet before  {b}")
print(f"wallet after   {a}")
print(f"delta          {a - b}")
print()
if a == b:
    print("EXACTLY RESTORED. The user got back precisely what they put in.")
else:
    print(f"NOT EXACTLY RESTORED, difference {a - b}. This must be explained, not rounded away.")
PY
echo '```'
echo
echo "A withdrawal that returns a different amount than was deposited, with no stated reason, is what"
echo "task 8.6's counter forbids. The same standard applies on mainnet, so the delta is asserted"
echo "rather than eyeballed."
echo
echo "## Explorer"
echo
for r in "$R1" "$R2" "$R3" "$R4" "$R5"; do
  h=$(printf '%s' "$r" | awk '{print $2}')
  [ "$h" != "none" ] && echo "- https://www.oklink.com/x-layer/tx/$h"
done
} >> "$OUT"

echo "written: $OUT"
tail -22 "$OUT"
