# Gas inventory, measured on testnet

Run 2026-08-16 05:44:37 UTC. Chain 1952. ZERO mainnet spend.

Every figure is either a RECEIPT from a transaction that ran, or an ESTIMATE from
eth_estimateGas against the live deployment. Each row says which, because an estimate and a
receipt are different kinds of number and mixing them is how a budget goes wrong in the
direction that matters.

## Deployment gas, from the deployed bytecode

Measured by asking the chain what each contract's creation cost, using the code size and the
actual deployment receipts recorded in deployments.json where available.

```
contract           address                                      runtime code bytes
MockERC20 tBASE    0x8FB4B7899EdE2D2015E9E03C9baFF9632C0bec84   2802
MockERC20 tQUOTE   0x5069c6C619EE23a8e2EBa15b4B95F7EE16869501   2802
OrderBookVenue     0xd79276538A39ae5247e7a0d33D40AaD849e09B4D   3513
RiskGuard          0x977A77aF8891187C73c7cdBd145B6fD57A0D0a47   3652
BatchExecutor      0x954A0B68B81dD4028631a7D1B98d80bf2a563142   2459
FeeCollector       0x2e0727C36c9F720E8d31C5eB3a3748A683610e38   2157
AgentVault         0x3e938422f11D53b62F6Fe4afa2e4f52B1aFF4382   4893
```

Deployment gas is roughly 200 gas per byte of runtime code plus 32,000 for the CREATE plus
execution of the constructor, so the byte counts above bound the deployment cost. The
authoritative figures are the RECEIPTS below, taken from transactions that actually ran.

## Transaction gas, from real receipts on chain 1952

```
operation                                gas used  source
BatchExecutor take, with approve legs      263036  receipt, task 7.6 first run
BatchExecutor take, legs removed           199448  receipt, task 7.6 after optimisation
agent cycle end to end                     255459  receipt, task 9.6
vault depositWithPermit                    146682  receipt, task 9.4
vault deposit, plain                       115689  receipt, task 9.3
vault withdrawAll                           52842  estimate, live deployment
vault setPaused                             26285  estimate, live deployment
token approve                               46556  estimate, live deployment
guard setMarketCap                          30467  estimate, live deployment
venue postOrder                            170404  estimate, live deployment
```

## What the mainnet plan actually needs

Phase 12 deploys the stack once and runs a small number of transactions. The deployment set is
the seven contracts above; the transaction set is the wiring calls plus one agent cycle plus
one user deposit and withdrawal.

Task 11.3 multiplies this inventory by the live mainnet gas price and states the answer in OKB
and in USD, with a stated margin.
