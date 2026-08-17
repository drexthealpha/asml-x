# Task 15.1: adversarial audit of the deployed fee and vault surfaces

Run 2026-08-16 19:14:50 UTC. Verdict: **PASS**

Chain 1952. Vault `0x3e938422f11D53b62F6Fe4afa2e4f52B1aFF4382`, FeeCollector `0x2e0727C36c9F720E8d31C5eB3a3748A683610e38`.
Attacker `0x00000000000000000000000000000000000000Ee`, an address this project holds no key for, chosen so it cannot be the owner,
the agent or a charger by accident.

## Why this is not what the Foundry tests already do

Those run against locally compiled bytecode. **This runs against what is actually deployed** at
the addresses the dashboard links to. A contract can pass its own suite and not be the contract
that reached the chain.

`cast call --from` makes the node execute the deployed bytecode with a hostile `msg.sender`,
which is precisely the question an access-control audit asks, at zero cost and with no second
keystore. Its limit is stated below rather than left implicit.

## Results

| call as the attacker | expected | got | verdict |
|---|---|---|---|
| `eve opens a trade on someone else's deposit` | `NotAgent()` = `0x0d9ab13f` | 0x0d9ab13f | PASS |
| `eve closes a trade` | `NotAgent()` = `0x0d9ab13f` | 0x0d9ab13f | PASS |
| `eve reassigns the agent to herself` | `NotOwner()` = `0x30cd7471` | 0x30cd7471 | PASS |
| `eve withdraws from an empty balance` | `InsufficientBalance(uint256,uint256)` = `0xcf479181` | 0xcf479181 | PASS |
| `eve deposits zero` | `ZeroAmount()` = `0x1f2a2005` | 0x1f2a2005 | PASS |
| `eve charges a fee, minting revenue` | `NotCharger()` = `0xd796045b` | 0xd796045b | PASS |
| `eve raises the fee rate` | `NotOwner()` = `0x30cd7471` | 0x30cd7471 | PASS |
| `eve points the treasury at herself` | `NotOwner()` = `0x30cd7471` | 0x30cd7471 | PASS |
| `eve authorises herself as a charger` | `NotOwner()` = `0x30cd7471` | 0x30cd7471 | PASS |
| `anyone may read the fee quote` | succeeds | 4900 | CONTROL |
| `anyone may read vault solvency` | succeeds | true | CONTROL |
| `anyone may read a withdrawable balance` | succeeds | 25000000000000000000 [2.5e19] | CONTROL |

9 refused as expected, 0 unexpected, 3 of 3 controls succeeded.

## The controls are the part that makes the refusals mean anything

A contract that reverted on every call would score a perfect refusal rate. The three reads
above are executed as the SAME attacker address and succeed, so the refusals are the access
control working rather than the contract being broken or the address being wrong.

## What this does NOT cover, stated rather than skipped

1. **Cases where funding, not authorisation, is the gate.** The attacker holds no balance, so
   `deposit` with a real amount cannot be distinguished here between refusal for want of an
   allowance and refusal by policy. Those paths are covered by the invariant campaign in 14.2,
   which reaches them with funded handlers.
2. **Reentrancy.** Not reachable through `eth_call` from an EOA, since it needs a hostile
   contract. The transient-storage guards are covered by the Foundry suite.
3. **The owner turning hostile.** Owner-authorised calls are refused for the attacker and would
   succeed for the owner, which is the design. What limits owner power is that pause can never
   block withdrawal, proved as an invariant in 14.2, not an access check here.

## Reproduce

```
bash scripts/178-adversarial-fee-vault.sh
```
