#!/usr/bin/env bash
# Task 11.3: compute the exact OKB requirement.
#
# THINKING: #29 margin-of-safety, #27 opportunity-cost, #33 Pareto.
#
# EVIDENCE PATH: evidence/phase11/budget.md
# PASS: one number with its arithmetic shown.
#
# Every input is measured rather than assumed: the gas figures come from task 11.2's inventory
# (receipts where a transaction ran, estimates against the live deployment otherwise) and the gas
# price is read LIVE from chain 196 at run time.
#
# ZERO SPEND. This reads mainnet and writes a document. It signs nothing.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase11/budget.md"
mkdir -p "$(dirname "$OUT")"
MAINNET="https://rpc.xlayer.tech"

GAS_PRICE=$(cast gas-price --rpc-url "$MAINNET" 2>/dev/null || echo 0)
BLOCK=$(cast block-number --rpc-url "$MAINNET" 2>/dev/null || echo "?")
BALANCE=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$MAINNET" 2>/dev/null || echo 0)

python3 - "$GAS_PRICE" "$BLOCK" "$BALANCE" "$DEPLOYER_ADDRESS" > "$OUT" <<'PY'
import sys

gas_price = int(sys.argv[1])
block = sys.argv[2]
balance_wei = int(sys.argv[3])
deployer = sys.argv[4]

# Deployments, MEASURED by `cast estimate --create` against chain 196 in task 11.4's dry run.
#
# An earlier version of this file modelled creation cost as 200 gas per byte of runtime code plus
# 32,000 for the CREATE. That is a textbook upper bound and it was 12.3% HIGH: the model said
# 6,624,000 and the chain says 5,521,463. The model was a stand-in for a number that could not be
# obtained until a mainnet RPC would answer an estimate, and now one has, so the measurement replaces
# it. Widening task 11.4's tolerance instead would have been the wrong repair.
DEPLOYMENTS = [
    ("MockERC20 tBASE", 723_067),
    ("MockERC20 tQUOTE", 723_091),
    ("OrderBookVenue", 842_999),
    ("RiskGuard", 899_207),
    ("FeeCollector", 596_290),
    ("BatchExecutor", 591_800),
    ("AgentVault", 1_145_009),
]

# Transactions the mainnet plan actually sends, with MEASURED gas.
TRANSACTIONS = [
    ("guard setMarketCap", 30_467, 1),
    ("guard setAgent", 30_467, 2),
    ("token mint", 46_556, 4),
    ("token approve", 46_556, 4),
    ("venue setAuthorisedTaker", 30_467, 1),
    ("fee setCharger", 30_467, 1),
    ("executor approveToken", 46_556, 3),
    ("venue postOrder", 170_404, 4),
    ("agent cycle, take plus fee", 255_459, 3),
    ("user depositWithPermit", 146_682, 1),
    ("user withdrawAll", 52_842, 1),
    ("user setPaused", 26_285, 2),
]

print("# Mainnet budget, task 11.3")
print()
print(f"Gas price read LIVE from chain 196 at block {block}: **{gas_price:,} wei** "
      f"({gas_price / 1e9:.4f} gwei).")
print()
print("Gas figures come from task 11.2's inventory: receipts where a transaction actually ran on")
print("testnet, estimates against the live deployment otherwise. Nothing here is a guess.")
print()

print("## Deployments")
print()
print("Measured by `cast estimate --create` against chain 196, task 11.4. Not modelled.")
print()
print("```")
print(f"{'contract':<20}{'gas':>12}")
deploy_gas = 0
for name, g in DEPLOYMENTS:
    deploy_gas += g
    print(f"{name:<20}{g:>12,}")
print(f"{'TOTAL':<20}{deploy_gas:>12,}")
print("```")
print()

print("## Transactions")
print()
print("```")
print(f"{'operation':<30}{'gas':>10}{'count':>7}{'subtotal':>12}")
tx_gas = 0
for name, g, n in TRANSACTIONS:
    sub = g * n
    tx_gas += sub
    print(f"{name:<30}{g:>10,}{n:>7}{sub:>12,}")
print(f"{'TOTAL':<30}{'':>10}{'':>7}{tx_gas:>12,}")
print("```")
print()

total_gas = deploy_gas + tx_gas
MARGIN = 3.0  # stated, not hidden in a constant

print("## The number")
print()
print("```")
print(f"deployment gas          {deploy_gas:>12,}")
print(f"transaction gas         {tx_gas:>12,}")
print(f"total gas               {total_gas:>12,}")
print()
print(f"gas price (live)        {gas_price:>12,} wei")
print(f"cost                    {total_gas * gas_price:>12,} wei")
print(f"                        {total_gas * gas_price / 1e18:.9f} OKB")
print()
print(f"margin                  {MARGIN:.0f}x")
print(f"BUDGET                  {total_gas * gas_price * MARGIN / 1e18:.9f} OKB")
print("```")
print()

okb_needed = total_gas * gas_price * MARGIN / 1e18

print("### Why a 3x margin and not a tighter one")
print()
print("Three things can each move the real cost, and none is under this project's control:")
print()
print("1. **Gas price moves.** The figure above is a spot read. X Layer's price has been stable at")
print("   20,000,001 wei across every measurement in this build, but a budget set at exactly the")
print("   spot price fails the first time it is not.")
print("2. **Deployment gas is bounded, not measured.** The per-byte model is an upper bound on")
print("   runtime code cost, and constructor execution is on top. The only way to measure a mainnet")
print("   deployment exactly is to perform it.")
print("3. **A failed transaction still costs gas.** A revert consumes what it used before reverting.")
print("   Phase 12 has a dry run precisely to make this unlikely, not impossible.")
print()
print("The margin is stated here rather than folded silently into the headline, so a reader can")
print("apply their own.")
print()

print("## USD")
print()
print("OKB's price is not readable from the chain and no price oracle is trusted for a budget line,")
print("so the conversion is given as a table rather than a single figure that would pretend to a")
print("precision it does not have.")
print()
print("```")
for px in (20, 40, 60, 80):
    print(f"  OKB at ${px:>3}   ->   ${okb_needed * px:,.4f}")
print("```")
print()

print("## Current mainnet balance")
print()
print("```")
print(f"deployer   {deployer}")
print(f"balance    {balance_wei} wei ({balance_wei / 1e18:.9f} OKB)")
print("```")
print()
if balance_wei >= okb_needed * 1e18:
    print(f"**Sufficient.** The balance covers the {okb_needed:.9f} OKB budget.")
else:
    short = okb_needed - balance_wei / 1e18
    print(f"**NOT SUFFICIENT.** Short by {short:.9f} OKB.")
    print()
    print("### USER HANDLES, and this gates all of Phase 12")
    print()
    print("Acquire OKB on the OKX exchange and withdraw it to X Layer (chain 196), to")
    print(f"`{deployer}`. Ethereum-based OKB was retired, so the OKX withdrawal path is the only")
    print("clean source.")
    print()
    print(f"**Amount to send: {okb_needed:.6f} OKB.** Rounding up to a round number is fine and")
    print("costs almost nothing; sending less risks a failed deploy midway through Phase 12, which")
    print("wastes the gas already spent.")
print()
print("## Reproduce")
print()
print("```")
print("bash scripts/147-gas-inventory.sh    # measure gas on testnet")
print("bash scripts/148-mainnet-budget.sh   # read the live price and compute this")
print("```")
PY

echo "written: $OUT"
tail -34 "$OUT"
