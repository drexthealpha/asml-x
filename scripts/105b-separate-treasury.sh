#!/usr/bin/env bash
# Task 7.6 follow-up: give the fee its own treasury address.
#
# FOUND BY THE CROSS-CHECK, not by the tests. The 7.6 gate compared the treasury's tQUOTE balance
# delta against the decoded feeAmount and got 20.1e18 against 0.1e18. Neither number was wrong: the
# treasury was the deployer, the deployer was also the MAKER of the resting order, and so the same
# balance received 20e18 of trade proceeds and 0.1e18 of fee in one transaction.
#
# That is not a test artifact, it is an accounting defect. With one address in both roles there is no
# way to state revenue from balances at all, and the growth surface in task 13.1 would be reporting a
# number that includes trading flow. The unit tests could never have caught it, because in Foundry the
# treasury is address(0xBEEF) and the maker is address(0x1111) by construction.
#
# The treasury below is a distinct address. On testnet its tQUOTE is not recoverable, which is
# acceptable for a test token and is the point: fee revenue should be somewhere that trading cannot
# touch. Task 12.1 assigns a real key-held treasury for mainnet.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

RPC="$XLAYER_TESTNET_RPC"
PASS="$(keystore_pass)"
J="$REPO/deployments.json"
FEE=$(python3 -c "import json;print(json.load(open('$J'))['feeCollector'])")

# A designated fee treasury, distinct from the deployer and from every market participant.
TREASURY=0x00000000000000000000000000000000FEE00001

echo "current treasury: $(cast call "$FEE" "treasury()(address)" --rpc-url "$RPC")"
cast send "$FEE" "setTreasury(address)" "$TREASURY" \
  --rpc-url "$RPC" --keystore "$KEYFILE" --password "$PASS" --json 2>/dev/null \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print('setTreasury',d['status'],d['transactionHash'])"

NEW=$(cast call "$FEE" "treasury()(address)" --rpc-url "$RPC")
echo "new treasury:     $NEW"

python3 - "$J" "$TREASURY" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["feeTreasury"] = sys.argv[2]
json.dump(d, open(p, "w"), indent=2)
print("deployments.json: feeTreasury recorded")
PY
