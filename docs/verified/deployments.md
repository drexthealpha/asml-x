# Deployments: X Layer testnet, chain 1952

Status: DEMONSTRATED. Every address below was deployed by
0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46 and read back from chain.
Captured 2026-08-16 00:16:25 UTC.

These are SELF-DEPLOYED contracts, not third-party venues. See
docs/decisions/ADR-001-venue-strategy.md for why, and what it costs.

| contract | address | role |
|---|---|---|
| MockERC20 tBASE | `0x8FB4B7899EdE2D2015E9E03C9baFF9632C0bec84` | TEST token, base asset |
| MockERC20 tQUOTE | `0x5069c6C619EE23a8e2EBa15b4B95F7EE16869501` | TEST token, quote asset |
| OrderBookVenue | `0xd79276538A39ae5247e7a0d33D40AaD849e09B4D` | escrowed limit order book |
| RiskGuard | `0x977A77aF8891187C73c7cdBd145B6fD57A0D0a47` | binding exposure caps and kill switch |
| BatchExecutor | `0x954A0B68B81dD4028631a7D1B98d80bf2a563142` | atomic multi-leg execution |
| FeeCollector | `0x2e0727C36c9F720E8d31C5eB3a3748A683610e38` | usage fee on executed notional, 50 bps, immutable 100 bps ceiling |

| AgentVault | `0x3e938422f11D53b62F6Fe4afa2e4f52B1aFF4382` | user custody: agent may trade, never withdraw |
Market id for tBASE/tQUOTE: `0x7cf714968d0c21fb12269a1a8e84bdc4fe973673c435100e04baae9b7c6b3fdd`

Explorer:

- venue: https://www.oklink.com/x-layer-testnet/address/0xd79276538A39ae5247e7a0d33D40AaD849e09B4D
- guard: https://www.oklink.com/x-layer-testnet/address/0x977A77aF8891187C73c7cdBd145B6fD57A0D0a47
- executor: https://www.oklink.com/x-layer-testnet/address/0x954A0B68B81dD4028631a7D1B98d80bf2a563142
- feeCollector: https://www.oklink.com/x-layer-testnet/address/0x2e0727C36c9F720E8d31C5eB3a3748A683610e38
- tBASE: https://www.oklink.com/x-layer-testnet/address/0x8FB4B7899EdE2D2015E9E03C9baFF9632C0bec84
- tQUOTE: https://www.oklink.com/x-layer-testnet/address/0x5069c6C619EE23a8e2EBa15b4B95F7EE16869501

## Configuration on chain

- guard.maxGross = 1000e18
- guard.maxPerMarket[tBASE/tQUOTE] = 500e18
- guard agents: BatchExecutor, deployer
- guard.killed = false
- venue.authorisedTakers[BatchExecutor] = true (nobody else can take; direct fills revert)
- fee.chargers[BatchExecutor] = true, fee.feeBps = 50, fee.MAX_FEE_BPS = 100
- BatchExecutor.feeCollector is immutable and every batch must end with a leg targeting it
