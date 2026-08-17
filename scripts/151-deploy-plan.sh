#!/usr/bin/env bash
# Task 11.5: deployment order and rollback.
#
# THINKING: #62 pre-mortem (assume step N failed with money already spent, and write what happens
# next BEFORE it happens), #11 systems, #23 second-order.
#
# EVIDENCE PATH: evidence/phase11/deploy-plan.md
# PASS: a written order with a stated recovery action for each step.
#
# The dependency order is DERIVED from the constructor arguments in the contracts, not remembered.
# A constructor argument is a hard dependency: a contract that takes an address cannot be deployed
# before the thing at that address exists.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase11/deploy-plan.md"
mkdir -p "$(dirname "$OUT")"

{
echo "# Mainnet deployment plan, order and rollback"
echo
echo "Written $(date -u '+%Y-%m-%d %H:%M:%S UTC'), BEFORE anything is deployed to chain 196."
echo
echo "## Constructor dependencies, read from the source"
echo
echo "A constructor argument is a hard ordering constraint: a contract taking an address cannot be"
echo "deployed before the thing at that address exists. These are extracted from the contracts"
echo "rather than recalled."
echo
echo '```'
} > "$OUT"

cd "$REPO/contracts"
for f in src/MockERC20.sol src/OrderBookVenue.sol src/RiskGuard.sol src/FeeCollector.sol \
         src/BatchExecutor.sol src/AgentVault.sol; do
  name=$(basename "$f" .sol)
  ctor=$(grep -A2 -m1 '    constructor(' "$f" | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-120)
  printf '  %-16s %s\n' "$name" "${ctor:-constructor() implicit}" >> "$OUT"
done

cat >> "$OUT" <<'MD'
```

## The order, and why each step is where it is

| # | step | depends on | why it cannot move earlier |
|---|---|---|---|
| 1 | deploy `MockERC20` aQUOTE | nothing | the asset every other contract references |
| 2 | deploy `MockERC20` aBASE | nothing | the other side of the market |
| 3 | deploy `OrderBookVenue` | nothing | takes no constructor args; its own owner is the deployer |
| 4 | deploy `RiskGuard` | nothing | takes only a gross cap |
| 5 | deploy `FeeCollector` | a treasury address | needs a treasury that is NOT the deployer, see below |
| 6 | deploy `BatchExecutor` | 4, 5 | constructor takes `(riskGuard, feeCollector)`, both immutable |
| 7 | deploy `AgentVault` | 1, 3 | constructor takes `(asset, tradeTarget)`, both immutable |
| 8 | `guard.setMarketCap` | 1, 2, 4 | market id is derived from the token pair |
| 9 | `guard.setAgent(executor)` | 4, 6 | |
| 10 | `venue.setAuthorisedTaker(executor)` | 3, 6 | without it every take reverts `NotAuthorisedTaker` |
| 11 | `fee.setCharger(executor)` | 5, 6 | without it every fee leg reverts `NotCharger` |
| 12 | `executor.approveToken(aQUOTE, venue)` | 1, 3, 6 | a take against a resting ASK spends quote |
| 13 | `executor.approveToken(aBASE, venue)` | 2, 3, 6 | a take against a resting BID spends BASE |
| 14 | `executor.approveToken(aQUOTE, fee)` | 1, 5, 6 | the fee leg pulls quote from the executor |
| 15 | `vault.setAgent(deployer)` | 7 | |
| 16 | mint and seed the book | 1, 2, 3 | the agent needs candidates or it reports a one-candidate defect |
| 17 | one agent cycle | all | the proof |

**Steps 12 and 13 are BOTH required and this is not redundancy.** Task 7.6 removed the per-batch
approve legs to save gas and granted only quote, and the first SELL on testnet reverted with
`LegFailed(1, venue, ...)`. The bug survived from Phase 7 to Phase 9 because every execution in
between happened to be a buy.

## Rollback: what to do when step N fails with money already spent

The governing fact is that **nothing before step 17 moves user funds**, and there are no users on
mainnet at deploy time. So the worst case at every step is wasted gas, never lost custody. The
recovery is almost always "fix and redeploy the affected contract onward", because the addresses are
written to `deployments.json` and every dependent is deployed after it.

| step fails | what is already spent | recovery |
|---|---|---|
| 1 to 4 | one deployment | redeploy that contract. Nothing references it yet. |
| 5 `FeeCollector` | 4 deployments | redeploy. Nothing references it yet. |
| 6 `BatchExecutor` | 5 deployments | redeploy. `riskGuard` and `feeCollector` are IMMUTABLE, so if either address was wrong the executor must be redeployed, not reconfigured. |
| 7 `AgentVault` | 6 deployments | redeploy. `asset` and `tradeTarget` are immutable, same reasoning. |
| 8 to 11 wiring | 7 deployments | retry the single call. These are owner-only setters and are idempotent. |
| 12 to 14 approvals | 7 deployments | retry. `approveToken` is idempotent. |
| 15 `vault.setAgent` | 7 deployments | retry. Idempotent. |
| 16 seeding | everything | retry. Posting more orders is additive and harmless. |
| 17 agent cycle reverts | everything | READ THE REVERT. A revert here is the system refusing, which may be correct behaviour rather than a failure. See below. |

### The one step where "retry" is the wrong instinct

If step 17 reverts, the first question is not how to make it pass. `LegFailed`,
`NotAuthorisedTaker`, `NotCharger` and `ExceedsUserLimit` each name a specific missing wiring step
and point at 10 through 14. But `hold outscored every permitted action` is **not a failure**: it is
the risk engine declining to trade, and forcing a trade past it would defeat the entire point of the
project. The correct response to a hold is to seed a book worth trading, which is what
`scripts/136-seed-executable-book.sh` does, and not to loosen a limit.

### Rollback that is NOT available, stated plainly

There is no upgrade path and no proxy. Every contract is immutable once deployed. That is a
deliberate property, recorded in `AgentVault`: "There is no owner withdrawal, no agent withdrawal, no
rescue function, no sweep, no upgrade path. Those are not omissions to be added later; every one of
them is an exit the operator could take."

So "roll back" always means "deploy a new one and update `deployments.json`", never "patch the live
one". The cost of that is one deployment's gas, which the dry run puts between 0.000012 and 0.000023
OKB per contract. The budget carries a 3x margin partly to absorb exactly this.

## The treasury must not be the deployer

Task 7.6 found this on testnet: with `treasury == maker == deployer`, a fee event and trade proceeds
land in the same balance and revenue cannot be stated from balances at all. The mainnet
`FeeCollector` takes a treasury address distinct from the deployer at step 5.

## Pre-flight checklist, to be run immediately before step 1

```
bash scripts/146-mainnet-facts.sh     # chain 196 is answering, gas price is sane
bash scripts/149-mainnet-dryrun.sh    # every step estimates, nonce unchanged
cast balance <deployer> --rpc-url https://rpc.xlayer.tech
```

The balance must exceed the budget in `evidence/phase11/budget.md`. As of writing it is 0.005 OKB
against a 0.000473 OKB budget, roughly 10x headroom.
MD

echo "written: $OUT"
grep -c "^" "$OUT" | sed 's/^/lines: /'
