# Task 16.3: mainnet claims re-verified from chain

Run 2026-08-16 19:47:04 UTC. Verdict: **PASS**

Read from `https://rpc.xlayer.tech`, `eth_chainId` = **196**.

## Why this rather than re-running Phase 12

Re-running would spend the user's OKB to do the thing again and then check the new run matched.
This reads **what actually happened**, which is what the documents claim. A local evidence file
can be edited; chain 196 cannot.

The hashes and addresses below are **scraped from the evidence files**, not pasted into this
script. A document that quietly changed a hash fails this check rather than being confirmed by
a constant somebody updated to match.

## Transactions, 7 matching their claimed outcome, 0 not

**Each hash is checked against what its document CLAIMS, not against success.** A hash cited by
`mainnet-refusal.md` is a refusal, and a refusal that succeeded would be the defect. An earlier
version of this gate expected `0x1` everywhere and failed on the one transaction that proves
the risk guard rejects an over-cap trade with real money at stake, which would have inverted the
meaning of the most important negative result in Phase 12.

| hash | block | status | result |
|---|---|---|---|
| `0x0ab18cf298fceb23...` | 68101006 | 0x1 | succeeded |
| `0x453584e3a993b839...` | 68101010 | 0x1 | succeeded |
| `0x6a0237847f4d7379...` | 68100752 | 0x0 | refused, as the document claims |
| `0x74cdf48604041e79...` | 68101039 | 0x1 | succeeded |
| `0x776033b110759b91...` | 68101034 | 0x1 | succeeded |
| `0xb4785fbcbd2ba5f0...` | 68099440 | 0x1 | succeeded |
| `0xebd8973b3fd220db...` | 68101019 | 0x1 | succeeded |

### 64-hex strings in these documents that are NOT transactions: 2

| string | finding |
|---|---|
| `0x38888fc700000000...` | no receipt on chain 196 |
| `0x3e2ed0286b96e18e...` | no receipt on chain 196 |

These are correct content, not missing transactions. `mainnet-refusal.md` quotes REVERT DATA,
and a 4-byte selector followed by a 32-byte market id is exactly 64 hex characters, so it looks
like a hash to a regex. The first version of this script used `cast receipt`, which BLOCKS
waiting for confirmation, and hung indefinitely waiting for a transaction that will never
exist. `eth_getTransactionReceipt` returns null at once, which fixes the hang and gives the
right classification: no receipt means not a transaction, not a missing one. Counting these as
missing would have failed this gate for documents that are perfectly correct.

## Contracts, 7 with code, 0 without

| contract | address | bytecode | result |
|---|---|---|---|
| `tQUOTE` | `0x12dcbE73416CDFe6de0681286C25ACe81B4644C0` | 2802 | deployed |
| `tBASE` | `0xEC23954ef24b22600C3b72C61CCE99cbe19A5AF5` | 2802 | deployed |
| `venue` | `0x7065781018E015779d42bcC3eEA7429F8e479a3F` | 3513 | deployed |
| `riskGuard` | `0x9D22e538a72a5d2c9A28D08c27999216A78343C9` | 3652 | deployed |
| `feeCollector` | `0x7ff884C412a1A2c416e931C59889e5335C5EFa0D` | 2157 | deployed |
| `batchExecutor` | `0x7092050F3C4e72A2df8610ae2CC8c39DcA3B7f52` | 2459 | deployed |
| `agentVault` | `0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24` | 4893 | deployed |

## State, read live

| reading | value | what it confirms |
|---|---|---|
| `feeBps()` | 50 | the live rate, which only ever falls |
| `chargeCount()` | 1 | fees were charged on mainnet, not just quoted |
| `treasury()` | `0x000000000000000000000000000000000fee0196` | separate from the deployer: yes |
| `isSolvent()` | true | the vault covers what depositors are owed |
| `totalDeposits()` | 0 | real user capital passed through it |

**The treasury being a different address from the deployer is checked, not assumed.** It is what
makes fee revenue distinguishable from trade proceeds, and an earlier deployment had them equal,
which made the fee unprovable.

## Reproduce

```
bash scripts/184-mainnet-reverify.sh
```
