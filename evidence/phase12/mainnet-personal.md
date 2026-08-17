# Task 12.5: a real user deposit and withdrawal on mainnet

Run 2026-08-16 08:47:13 UTC. **Chain id 196.**

Personal mode is not testnet-only: the same AgentVault, the same three operations, on 196.

```
AgentVault        0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24
asset             0x12dcbE73416CDFe6de0681286C25ACe81B4644C0
wallet before     2982900000000000000000
```

## 1. Deposit

```
approve   0x1 0x0ab18cf298fceb230916aeb89805f8f63e1bf8b11ae63dbdb2460a0ddcf99024
deposit   0x1 0x453584e3a993b8394bfc0d1b1e09bf2704455c912764fb86f078e5e12aac6836
vault balance  5000000000000000000
user limit     5000000000000000000
```

## 2. An agent action under that deposit

```
openTrade 2 aQUOTE   0x1 0xebd8973b3fd220dbcdb106672780d83cdbc2c8342eb6a6f54d90d97d43bff028
committed            2000000000000000000
withdrawable         3000000000000000000
```

The agent moved 2 aQUOTE to the venue and it is no longer withdrawable, which is the point:
the same tokens cannot be both traded and withdrawn.

## 3. Close and withdraw in full

```
closeTrade   0x1 0x776033b110759b9167dd8e578c700159edc89d20d51e0286335df0bd5fcbb10d
withdrawAll  0x1 0x74cdf48604041e79ad778d8af8d0c9a6c108795e7120c3ae9f5387bb3fd46ea4
vault balance after  0
wallet after         2980900000000000000000
```

## The restoration assertion

```
wallet before  2982900000000000000000
wallet after   2980900000000000000000
delta          -2000000000000000000

NOT EXACTLY RESTORED, difference -2000000000000000000. This must be explained, not rounded away.
```

A withdrawal that returns a different amount than was deposited, with no stated reason, is what
task 8.6's counter forbids. The same standard applies on mainnet, so the delta is asserted
rather than eyeballed.

## Explorer

- https://www.oklink.com/x-layer/tx/0x0ab18cf298fceb230916aeb89805f8f63e1bf8b11ae63dbdb2460a0ddcf99024
- https://www.oklink.com/x-layer/tx/0x453584e3a993b8394bfc0d1b1e09bf2704455c912764fb86f078e5e12aac6836
- https://www.oklink.com/x-layer/tx/0xebd8973b3fd220dbcdb106672780d83cdbc2c8342eb6a6f54d90d97d43bff028
- https://www.oklink.com/x-layer/tx/0x776033b110759b9167dd8e578c700159edc89d20d51e0286335df0bd5fcbb10d
- https://www.oklink.com/x-layer/tx/0x74cdf48604041e79ad778d8af8d0c9a6c108795e7120c3ae9f5387bb3fd46ea4


## THE -2 aQUOTE DELTA, EXPLAINED RATHER THAN ROUNDED AWAY

The assertion fired, and it was right to. Here is where the tokens actually are, read from chain 196
after the cycle:

```
venue          0x7065781018E015779d42bcC3eEA7429F8e479a3F   16.25 aQUOTE
agentVault     0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24    0
feeCollector   0x7ff884C412a1A2c416e931C59889e5335C5EFa0D    0
deployer                                                     2980.9 aQUOTE

user position inside the vault
  balanceOf      0
  committed      0
  totalDeposits  0
  isSolvent      true
```

**The vault behaved correctly and the user's deposit was fully restored: 5 aQUOTE in, 5 aQUOTE out.**

The delta comes from the test setup, not the contract. Trace it:

| step | wallet | where the tokens went |
|---|---|---|
| deposit 5 | -5 | wallet to vault |
| `openTrade` 2 | 0 | **vault to VENUE**, because the venue is the immutable `tradeTarget` |
| `closeTrade(2, 2)` | -2 | `transferFrom(msg.sender, ...)`, so the AGENT funded the return |
| `withdrawAll` | +5 | vault to wallet, the full deposit |
| net | **-2** | and the 2 is sitting at the venue |

`AgentVault.closeTrade` pulls the returned amount from `msg.sender`, which is the agent. On this
deployment **the agent and the user are the same address**, so one wallet paid both sides. In
production they are different parties: the agent returns funds from trading proceeds, and the user's
wallet only ever sees the deposit leaving and the withdrawal arriving.

So the correct reading is that the USER was made whole and the AGENT spent 2 aQUOTE funding a close
whose corresponding proceeds are still resting at the venue. `isSolvent()` returning true is the
contract confirming it: the vault owes nothing it cannot pay.

### Why this is recorded rather than fixed

The test could be made to show a clean zero by using a separate agent address, and that would be a
more realistic staging. It would also be a change made to produce a nicer number after the number
came out wrong, which is the wrong order to do things in. The assertion did its job: it refused to
accept a restored balance that was not restored, and the explanation is a real one that the chain
supports rather than a rationalisation.

**The claim this evidence supports is precise:** a real deposit, a real agent action under a real
per-user limit, and a real full withdrawal, all on chain 196, with the vault left solvent and the
user's vault balance back to zero. It does NOT claim the operator's wallet is unchanged, because it
is not, and the reason is stated above.
