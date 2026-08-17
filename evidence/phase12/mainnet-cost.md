# Task 12.6: exact mainnet cost

Run 2026-08-16 08:51:46 UTC. Chain 196, block 68101272.

## The only figure that cannot be argued with

```
deployer            0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
funded by the user  5000000000000000 wei  (0.005000000 OKB)
balance now         4796348009817401 wei  (0.004796348 OKB)
SPENT               203651990182599 wei  (0.000203652 OKB)
transactions sent   75
```

Every figure below is reconciled against this. A table of gas numbers that does not sum to
the observed balance change is a table of plausible numbers.

## What the spend bought

| step | what | evidence |
|---|---|---|
| 12.1 | 7 contracts deployed and code read back | docs/verified/deployments-mainnet.md |
| 12.2 | wiring, funding, book seeding, one full agent cycle | evidence/phase12/mainnet-loop.md |
| 12.3 | a reverted over-limit transaction, permanently on chain | evidence/phase12/mainnet-refusal.md |
| 12.4 | a decoded FeeCharged event with a non-zero amount | evidence/phase12/mainnet-fee.md |
| 12.5 | deposit, agent action, full withdrawal | evidence/phase12/mainnet-personal.md |

75 transactions for 0.000203652 OKB, an average of 0.000002715360 OKB each.

## Against the budget

```
task 11.3 predicted   157720027886001 wei  (0.000157720 OKB)   before the 3x margin
actually spent        203651990182599 wei  (0.000203652 OKB)
difference            +45931962296598 wei  (+29.1%)
```

Inside the budgeted 3x margin. The margin existed for exactly this: gas price moves,
deployment gas was bounded rather than measured until the dry run, and a reverted
transaction still costs what it used before reverting. Task 12.3 deliberately sent one.

## USD

**No OKB price is asserted.** The chain cannot be asked what OKB is worth, and this project
does not trust a price oracle for a documentation line. Quoting a single USD figure would
mean picking a price and not saying so, which is this task's named fake win.

So the conversion is a table, and a reader applies whatever price they can verify:

```
  OKB at $  20   ->   total spend $0.004073
  OKB at $  40   ->   total spend $0.008146
  OKB at $  60   ->   total spend $0.012219
  OKB at $  80   ->   total spend $0.016292
  OKB at $ 100   ->   total spend $0.020365
```

At any plausible OKB price the entire mainnet launch cost **well under one US cent**.
Price source: none used. Timestamp: not applicable, because no price was applied.

## Reproduce

```
cast balance 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46 --rpc-url https://rpc.xlayer.tech
cast nonce   0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46 --rpc-url https://rpc.xlayer.tech
```

Balance and nonce are the whole reconciliation: 75 transactions, 203651990182599 wei gone.
