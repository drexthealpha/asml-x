# Phase 12 gate: MAINNET LAUNCH

Closed 2026-08-16. **X Layer mainnet, chain 196.** Mandatory for eligibility, and met.

**CLOCK STOPS HERE (TASKS.md):** loop, refusal, fee event and a real user deposit, all live on 196
with hashes and costs.

## Subtasks

| # | task | verdict |
|---|---|---|
| 12.1 | deploy the minimal high-signal set | PASS, 7 contracts, code read back |
| 12.2 | a complete agent loop on mainnet | PASS, block 68099407, tx `0xb4785fbc...` |
| 12.3 | an explicit risk refusal on mainnet | PASS, reverted tx at block 68100752 |
| 12.4 | a live fee event on mainnet | PASS, decoded `FeeCharged`, 0.01425 aQUOTE |
| 12.5 | a real user deposit and withdrawal | PASS, 5 tx, vault solvent |
| 12.6 | exact gas and USD | PASS, reconciled against the balance delta |
| 12.7 | one click from the JUDGE-GUIDE | PASS for the UI, JUDGE-GUIDE outstanding to Phase 17 |

Claims C-1200 through C-1206.

## The contracts, live on 196

```
aQUOTE          0x12dcbE73416CDFe6de0681286C25ACe81B4644C0
aBASE           0xEC23954ef24b22600C3b72C61CCE99cbe19A5AF5
OrderBookVenue  0x7065781018E015779d42bcC3eEA7429F8e479a3F
RiskGuard       0x9D22e538a72a5d2c9A28D08c27999216A78343C9
FeeCollector    0x7ff884C412a1A2c416e931C59889e5335C5EFa0D
BatchExecutor   0x7092050F3C4e72A2df8610ae2CC8c39DcA3B7f52
AgentVault      0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24
fee treasury    0x000000000000000000000000000000000FEE0196   (NOT the deployer)
```

## The cost

```
funded by the user   0.005000000 OKB
spent                0.000203652 OKB
transactions         75
```

Under two US cents at any plausible OKB price. **No USD figure is asserted**: the chain cannot be
asked what OKB is worth and no price oracle is trusted for a documentation line, so 12.6 gives a
table across prices instead of one number with a hidden assumption. That is this task's named fake
win, refused.

Against the budget: 0.000158 OKB predicted before margin, 0.000204 actual, +29%. Inside the 3x
margin, which existed for exactly this. Task 12.3 also deliberately sent a transaction designed to
revert, and a revert still costs what it used.

## FAKE WIN REGISTER

| named fake win | fired? |
|---|---|
| 12.1 deploying and never using them | No. 12.2 through 12.5 transact against every contract. |
| 12.3 showing the testnet refusal captioned as mainnet | No. Chain id and mainnet block number on every artifact. |
| 12.6 a USD figure without saying what price was used | No. No price applied; a table is given instead. |

## Defects this phase found

**1. The runtime's network was a compile-time constant.** `RPC` and `EXPECTED_CHAIN_ID` were pinned
to testnet 1952. The first mainnet attempt pointed the runtime at mainnet ADDRESSES while it kept
reading the testnet RPC, so `orderCount()` returned no bytes and the cycle halted with `RpcFailure`.

**The chain check is what caught it**, so it was made configurable rather than removed. A mainnet run
now also refuses to fall back to the testnet secondary: silently reading a different chain's state
and reporting it as mainnet is worse than failing.

**2. The submit shim was hardcoded to the testnet RPC** for the same reason, found the same way.

**3. The transaction explorer URL redirects, and the fix for addresses did not cover it.** Task 11.1
had already found `/x-layer/address/` redirecting to `/x-layer/evm/address/` and corrected it.
Loading a real TRANSACTION url for 12.7 showed `/x-layer/tx/` redirects to `/x-layer/evm/tx/` too.
`curl -L` follows both silently and reports 200, so neither stale form looks wrong from a shell.

**4. The 12.5 restoration assertion fired**, wallet delta -2 aQUOTE, and the tokens were followed
rather than the number rounded away. The vault is correct and solvent: 5 aQUOTE in, 5 out, user
position zero. The delta is because `closeTrade` pulls from `msg.sender`, and on this deployment the
agent and the user are the same address, so one wallet funded both sides while the proceeds rest at
the venue. Recorded rather than fixed by using a separate agent address, because changing the test
after the number came out wrong is the wrong order.

## What is deliberately NOT claimed

- The JUDGE-GUIDE does not exist yet, so 12.7 is a pass for the UI surface only.
- No USD cost is stated as a fact.
- The agent traded a book this project seeded on its own venue. `OrderBookVenue` is a SELF-DEPLOYED
  STAND-IN and is labelled that way everywhere, because task 11.6 established four ways that Exchange
  OS has no usable developer surface on mainnet.
