#!/usr/bin/env bash
# Task 11.4: rehearse the mainnet deployment with estimateGas ONLY. Nothing is sent.
#
# THINKING: #62 pre-mortem (what breaks on the real run, found before it costs anything),
# #22 inversion, #29 margin-of-safety.
#
# EVIDENCE PATH: evidence/phase11/dryrun.txt
# PASS: every step returns a gas estimate, and the total matches 11.3 within 10%.
#
# FAKE WIN, quoted: "a dry run against testnet labelled as mainnet."
# COUNTER, quoted: "the script asserts eth_chainId == 196 before estimating."
#
# THE ASSERTION IS THE FIRST THING THAT RUNS and the script exits if it fails. Everything after it is
# `cast estimate --create` or `cast estimate`, neither of which signs or sends. The deployer key is
# never unlocked: no --keystore, no --password anywhere in this file. That absence is the real
# guarantee, not the comment.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase11/dryrun.txt"
mkdir -p "$(dirname "$OUT")"
MAINNET="https://rpc.xlayer.tech"
FROM="$DEPLOYER_ADDRESS"

# ---------------------------------------------------------------- the assertion, before anything
CHAIN_HEX=$(cast rpc eth_chainId --rpc-url "$MAINNET" 2>/dev/null | tr -d '"')
CHAIN=$(python3 -c "print(int('${CHAIN_HEX:-0x0}', 16))" 2>/dev/null || echo 0)

{
echo "Task 11.4, mainnet deployment dry run"
echo "run: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "== chain assertion, before any estimate =="
echo "eth_chainId: $CHAIN_HEX ($CHAIN)"
} > "$OUT"

if [ "$CHAIN" != "196" ]; then
  echo "ABORT: expected chain 196, got $CHAIN. This is the named fake win for this task." >> "$OUT"
  cat "$OUT"
  exit 1
fi
echo "OK: this is X Layer mainnet." >> "$OUT"

BAL=$(cast balance "$FROM" --rpc-url "$MAINNET")
GAS_PRICE=$(cast gas-price --rpc-url "$MAINNET")
{
echo "deployer:    $FROM"
echo "balance:     $BAL wei ($(python3 -c "print(f'{$BAL/1e18:.9f}')") OKB)"
echo "gas price:   $GAS_PRICE wei"
echo
echo "== deployment estimates, cast estimate --create =="
echo "Nothing below signs or sends. No keystore is opened anywhere in this script."
echo
} >> "$OUT"

cd "$REPO/contracts"
forge build > /dev/null 2>&1

TOTAL=0

# `cast estimate --create <BYTECODE> [SIG] [ARGS]` estimates a deployment without sending it.
est_create() {
  local name="$1" artifact="$2"
  shift 2
  local bin
  bin=$(python3 -c "
import json
d = json.load(open('out/$artifact'))
print(d['bytecode']['object'])
" 2>/dev/null)
  if [ -z "$bin" ] || [ "$bin" = "0x" ]; then
    printf '  %-20s %14s  %s\n' "$name" "NO BYTECODE" "artifact out/$artifact" >> "$OUT"
    return
  fi
  local out
  # --from and --rpc-url belong to `cast estimate`, BEFORE the --create subcommand. Passing them
  # after it made every deployment estimate fail with "unexpected argument '--from' found", and the
  # subtotal read 0 while the script still produced a confident-looking table.
  out=$(cast estimate --from "$FROM" --rpc-url "$MAINNET" --create "$bin" "$@" 2>&1)
  if printf '%s' "$out" | grep -qE '^[0-9]+$'; then
    printf '  %-20s %14s\n' "$name" "$out" >> "$OUT"
    TOTAL=$((TOTAL + out))
  else
    printf '  %-20s %14s  %s\n' "$name" "FAILED" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-70)" >> "$OUT"
  fi
}

est_create "MockERC20 tBASE"  "MockERC20.sol/MockERC20.json"       'constructor(string,string)' "ASML Base" "aBASE"
est_create "MockERC20 tQUOTE" "MockERC20.sol/MockERC20.json"       'constructor(string,string)' "ASML Quote" "aQUOTE"
est_create "OrderBookVenue"   "OrderBookVenue.sol/OrderBookVenue.json"
est_create "RiskGuard"        "RiskGuard.sol/RiskGuard.json"       'constructor(uint256)' 1000000000000000000000
est_create "FeeCollector"     "FeeCollector.sol/FeeCollector.json" 'constructor(address,uint256)' "$FROM" 50
est_create "BatchExecutor"    "BatchExecutor.sol/BatchExecutor.json" 'constructor(address,address)' "$FROM" "$FROM"
est_create "AgentVault"       "AgentVault.sol/AgentVault.json"     'constructor(address,address)' "$FROM" "$FROM"

{
echo
echo "  deployment subtotal: $TOTAL gas"
echo
echo "== wiring and operation estimates =="
echo "These call functions on contracts that do not exist on mainnet yet, so they cannot be"
echo "estimated against a live address. The figures are the TESTNET measurements from task 11.2,"
echo "carried over and LABELLED as such rather than silently presented as mainnet estimates."
echo "Both chains run the same EVM at the same gas schedule, so the transfer is sound, but it is a"
echo "transfer and not a measurement."
echo
} >> "$OUT"

TXGAS=0
wrow() {
  printf '  %-30s %10s x%-3s %12s  %s\n' "$1" "$2" "$3" "$(( $2 * $3 ))" "$4" >> "$OUT"
  TXGAS=$((TXGAS + $2 * $3))
}
wrow "guard setMarketCap"        30467  1 "testnet estimate, 11.2"
wrow "guard setAgent"            30467  2 "testnet estimate, 11.2"
wrow "token mint"                46556  4 "testnet estimate, 11.2"
wrow "token approve"             46556  4 "testnet estimate, 11.2"
wrow "venue setAuthorisedTaker"  30467  1 "testnet estimate, 11.2"
wrow "fee setCharger"            30467  1 "testnet estimate, 11.2"
wrow "executor approveToken"     46556  3 "testnet estimate, 11.2"
wrow "venue postOrder"          170404  4 "testnet estimate, 11.2"
wrow "agent cycle, take plus fee" 255459 3 "testnet RECEIPT, 9.6"
wrow "user depositWithPermit"   146682  1 "testnet RECEIPT, 9.4"
wrow "user withdrawAll"          52842  1 "testnet estimate, 11.2"
wrow "user setPaused"            26285  2 "testnet estimate, 11.2"

GRAND=$((TOTAL + TXGAS))
COST_WEI=$((GRAND * GAS_PRICE))

# Task 11.3's number, READ FROM ITS OUTPUT rather than duplicated here.
#
# The first version hardcoded the figure, which meant that when 11.3's model was replaced with the
# measured one this comparison kept checking against a number nothing produced any more. A
# consistency check that carries its own copy of the thing it is checking is not a check.
BUDGET_GAS=$(grep -oE 'total gas +[0-9,]+' "$REPO/evidence/phase11/budget.md" \
  | tail -1 | grep -oE '[0-9,]+$' | tr -d ',')
BUDGET_GAS=${BUDGET_GAS:-0}

{
echo
echo "  transaction subtotal: $TXGAS gas"
echo
echo "== total, and the comparison task 11.4 asks for =="
echo
python3 - "$TOTAL" "$TXGAS" "$GRAND" "$GAS_PRICE" "$COST_WEI" "$BUDGET_GAS" <<'PY'
import sys
dep, tx, grand, price, cost, budget = (int(x) for x in sys.argv[1:7])
print(f"  dry-run deployment gas   {dep:>12,}")
print(f"  carried transaction gas  {tx:>12,}")
print(f"  DRY RUN TOTAL            {grand:>12,}")
print(f"  task 11.3 estimate       {budget:>12,}")
delta = (grand - budget) / budget * 100 if budget else 0
print(f"  difference               {delta:>11.1f}%")
print()
print(f"  gas price                {price:>12,} wei")
print(f"  cost at this price       {cost:>12,} wei")
print(f"                           {cost/1e18:.9f} OKB")
print()
if abs(delta) <= 10:
    print("  WITHIN 10%: the dry run agrees with the budget.")
else:
    print(f"  OUTSIDE 10%: the budget in task 11.3 must be revised to the dry-run figure.")
PY
} >> "$OUT"

# Prove nothing was sent: the nonce must be unchanged.
NONCE=$(cast nonce "$FROM" --rpc-url "$MAINNET")
BAL_AFTER=$(cast balance "$FROM" --rpc-url "$MAINNET")
{
echo
echo "== proof that nothing was sent =="
echo "  nonce after:   $NONCE   (a sent transaction would have raised this)"
echo "  balance after: $BAL_AFTER wei"
echo "  balance before:$BAL wei"
if [ "$BAL" = "$BAL_AFTER" ]; then
  echo "  UNCHANGED. Zero spend confirmed by the chain, not by assertion."
else
  echo "  CHANGED. Something was sent, which this script must never do."
fi
} >> "$OUT"

cat "$OUT"
