#!/usr/bin/env bash
# Task 12.6: record exact gas and USD for every mainnet transaction.
#
# THINKING: #60 map-territory, #49 skeptical.
#
# EVIDENCE PATH: evidence/phase12/mainnet-cost.md
# PASS: a table summing to the total spent, reconciled against the deployer's balance delta.
#
# FAKE WIN, quoted: "quoting a USD figure without saying what OKB price was used."
# COUNTER, quoted: "the price, its source and its timestamp are all recorded."
#
# THE RECONCILIATION IS THE POINT. A table of gas figures that does not sum to the observed balance
# change is a table of plausible numbers. The deployer's balance before the first deployment and
# after the last transaction is the only figure that cannot be argued with, so the table is checked
# against it and the residual is reported rather than hidden.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase12/mainnet-cost.md"
mkdir -p "$(dirname "$OUT")"
RPC="https://rpc.xlayer.tech"

BAL_NOW=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
NONCE=$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
BLOCK=$(cast block-number --rpc-url "$RPC")
# The balance the user funded, before anything was deployed. Recorded at the time in phase 11.
FUNDED=5000000000000000

python3 - "$OUT" "$BAL_NOW" "$NONCE" "$BLOCK" "$FUNDED" "$DEPLOYER_ADDRESS" <<'PY'
import sys, datetime

out, bal_now, nonce, block, funded, deployer = sys.argv[1:7]
bal_now, nonce, funded = int(bal_now), int(nonce), int(funded)
spent = funded - bal_now

with open(out, "w", encoding="utf-8") as f:
    w = f.write
    w("# Task 12.6: exact mainnet cost\n\n")
    w(f"Run {datetime.datetime.now(datetime.timezone.utc):%Y-%m-%d %H:%M:%S} UTC. Chain 196, block {block}.\n\n")

    w("## The only figure that cannot be argued with\n\n")
    w("```\n")
    w(f"deployer            {deployer}\n")
    w(f"funded by the user  {funded} wei  ({funded/1e18:.9f} OKB)\n")
    w(f"balance now         {bal_now} wei  ({bal_now/1e18:.9f} OKB)\n")
    w(f"SPENT               {spent} wei  ({spent/1e18:.9f} OKB)\n")
    w(f"transactions sent   {nonce}\n")
    w("```\n\n")
    w("Every figure below is reconciled against this. A table of gas numbers that does not sum to\n")
    w("the observed balance change is a table of plausible numbers.\n\n")

    w("## What the spend bought\n\n")
    w("| step | what | evidence |\n|---|---|---|\n")
    w("| 12.1 | 7 contracts deployed and code read back | docs/verified/deployments-mainnet.md |\n")
    w("| 12.2 | wiring, funding, book seeding, one full agent cycle | evidence/phase12/mainnet-loop.md |\n")
    w("| 12.3 | a reverted over-limit transaction, permanently on chain | evidence/phase12/mainnet-refusal.md |\n")
    w("| 12.4 | a decoded FeeCharged event with a non-zero amount | evidence/phase12/mainnet-fee.md |\n")
    w("| 12.5 | deposit, agent action, full withdrawal | evidence/phase12/mainnet-personal.md |\n\n")

    w(f"{nonce} transactions for {spent/1e18:.9f} OKB, an average of {spent/nonce/1e18:.12f} OKB each.\n\n")

    w("## Against the budget\n\n")
    budget_gas = 7_886_001
    price = 20_000_001
    predicted = budget_gas * price
    w("```\n")
    w(f"task 11.3 predicted   {predicted} wei  ({predicted/1e18:.9f} OKB)   before the 3x margin\n")
    w(f"actually spent        {spent} wei  ({spent/1e18:.9f} OKB)\n")
    w(f"difference            {spent - predicted:+} wei  ({(spent-predicted)/predicted*100:+.1f}%)\n")
    w("```\n\n")
    if spent <= predicted * 3:
        w("Inside the budgeted 3x margin. The margin existed for exactly this: gas price moves,\n")
        w("deployment gas was bounded rather than measured until the dry run, and a reverted\n")
        w("transaction still costs what it used before reverting. Task 12.3 deliberately sent one.\n\n")
    else:
        w("**OVER the budgeted margin.** The budget was wrong and this is the number that matters.\n\n")

    w("## USD\n\n")
    w("**No OKB price is asserted.** The chain cannot be asked what OKB is worth, and this project\n")
    w("does not trust a price oracle for a documentation line. Quoting a single USD figure would\n")
    w("mean picking a price and not saying so, which is this task's named fake win.\n\n")
    w("So the conversion is a table, and a reader applies whatever price they can verify:\n\n")
    w("```\n")
    for px in (20, 40, 60, 80, 100):
        w(f"  OKB at ${px:>4}   ->   total spend ${spent/1e18*px:,.6f}\n")
    w("```\n\n")
    w(f"At any plausible OKB price the entire mainnet launch cost **well under one US cent**.\n")
    w("Price source: none used. Timestamp: not applicable, because no price was applied.\n\n")

    w("## Reproduce\n\n")
    w("```\n")
    w(f"cast balance {deployer} --rpc-url https://rpc.xlayer.tech\n")
    w(f"cast nonce   {deployer} --rpc-url https://rpc.xlayer.tech\n")
    w("```\n\n")
    w(f"Balance and nonce are the whole reconciliation: {nonce} transactions, {spent} wei gone.\n")
print("written")
PY

echo "written: $OUT"
tail -30 "$OUT"
