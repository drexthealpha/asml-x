# What is actually on X Layer testnet, chain 1952

Verified 9 Aug 2026 from onchain evidence only. Tasks 0.2.1, 0.2.2, 1.3.8.
Status: DEMONSTRATED. Every line below is a live RPC read, not a doc claim.

## Architecture: settled, and my earlier either/or framing was wrong

BLOCKER-LOG-002 is CLOSED by bytecode, not by prose. All OP Stack Bedrock
predeploys are present:

| Predeploy | Address | Bytecode |
|---|---|---|
| WETH | 0x4200...0006 | 5,695 chars |
| L2StandardBridge | 0x4200...0010 | 4,121 |
| SequencerFeeVault | 0x4200...0011 | 4,121 |
| L1Block | 0x4200...0015 | 4,121 |
| L2ToL1MessagePasser | 0x4200...0016 | 4,121 |

Corroborating: block `miner` is `0x4200...0011` (SequencerFeeVault), the OP Stack
signature. `L1Block.number()` returns 11449046, a real L1 block height.

Conclusion: the EXECUTION layer is OP Stack Bedrock, unambiguously. The AggLayer
and ZK-certificate machinery in the docs concerns settlement and proving, not
execution. Both docs were describing different layers, and the "OP Stack versus
Polygon CDK" question was malformed.

Consequence for the risk engine: use OP Stack finality semantics for reorg
handling, and treat AggLayer certificate submission as the L1 settlement gate.

## Measured chain facts

| Fact | Value |
|---|---|
| chain id | 1952 |
| primary rpc | https://testrpc.xlayer.tech |
| fallback rpc | https://xlayer-testnet.drpc.org |
| block time, measured twice | 7 blocks / 7s and 15 blocks / 12s, so ~1.0s |
| gas limit | 210,000,000 |
| base fee | 20,000,000 wei (0.02 gwei) |
| gas price | 20,000,001 wei |

## Available infrastructure

| Contract | Status |
|---|---|
| Multicall3 (0xcA11...CA11) | PRESENT, 7,619 chars. Use for the data pipeline |
| Permit2 (0x0000...8BA3) | PRESENT, 18,307 chars |
| CREATE2 deterministic deployer (0x4e59...956C) | PRESENT |
| ERC-4337 EntryPoint v0.7 (0x0000...a032) | PRESENT and in active use |
| ERC-4337 EntryPoint v0.6 (0x5ff1...2789) | PRESENT and in active use |
| Uniswap V2 Factory, V3 Factory, SwapRouter02, Position Manager | ABSENT at all canonical addresses |
| Seaport | ABSENT |

## Activity: the chain is effectively empty

300 consecutive blocks sampled (roughly 5 minutes of chain time):

| Metric | Value |
|---|---|
| total transactions | 410 |
| of which the mandatory L1Block system tx | 300 (one per block) |
| actual user transactions | 110 |
| distinct target contracts | 7 |
| distinct senders | 51 |
| busiest non-system targets | 0x7338fa94...58e1 (60 txs), 0xf6d08812...8907 (45 txs), unidentified, follow-up |

## Consequence for the hybrid venue decision

The approved plan was: real third-party DEX for spot and perps, own contracts for
outcome markets and RWA. Leg one has no substrate. There is no Uniswap at any
canonical address, and 110 user transactions across 7 contracts in five minutes
means there is no venue with meaningful liquidity to integrate against.

So the hybrid collapses, by force of evidence, to: deploy our own minimal venue
contracts on chain 1952 as the execution substrate for every vertical, and label
them plainly as such in the UI, README, and demo. This was already inside the
approved option, it is now the whole of it.

What this preserves: every transaction remains real, onchain, and explorer
verifiable, so rule R6 still holds fully.

What this costs, stated rather than hidden: "deep Exchange OS integration" cannot
be demonstrated, and "integration with X Layer" rests on real deploys, real txs,
OP Stack predeploy use, and Multicall3 rather than on venue-level integration.
The judge-facing framing must say exactly that.
