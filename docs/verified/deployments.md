# Deployments: X Layer testnet, chain 1952

Status: DEMONSTRATED. Every address below was deployed by
0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46 and read back from chain.
Captured 2026-08-09 07:39:02 UTC.

These are SELF-DEPLOYED contracts, not third-party venues. See
docs/decisions/ADR-001-venue-strategy.md for why, and what it costs.

| contract | address | role |
|---|---|---|
| MockERC20 tBASE | `0x9D22e538a72a5d2c9A28D08c27999216A78343C9` | TEST token, base asset |
| MockERC20 tQUOTE | `0x7ff884C412a1A2c416e931C59889e5335C5EFa0D` | TEST token, quote asset |
| OrderBookVenue | `0x7092050F3C4e72A2df8610ae2CC8c39DcA3B7f52` | escrowed limit order book |
| RiskGuard | `0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24` | binding exposure caps and kill switch |
| BatchExecutor | `0x81beCFdE5ad4692Dc52F7eA6B9DEA0C5f1694d5e` | atomic multi-leg execution |

Market id for tBASE/tQUOTE: `0x9b14309189a210d9c57d8f9988110c977884ed7629791ee202706dc43dbaab0e`

Explorer:

- venue: https://www.oklink.com/x-layer-testnet/address/0x7092050F3C4e72A2df8610ae2CC8c39DcA3B7f52
- guard: https://www.oklink.com/x-layer-testnet/address/0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24
- executor: https://www.oklink.com/x-layer-testnet/address/0x81beCFdE5ad4692Dc52F7eA6B9DEA0C5f1694d5e
- tBASE: https://www.oklink.com/x-layer-testnet/address/0x9D22e538a72a5d2c9A28D08c27999216A78343C9
- tQUOTE: https://www.oklink.com/x-layer-testnet/address/0x7ff884C412a1A2c416e931C59889e5335C5EFa0D

## Configuration on chain

- guard.maxGross = 1000e18
- guard.maxPerMarket[tBASE/tQUOTE] = 500e18
- guard agents: BatchExecutor, deployer
- guard.killed = false

## RWA stand-in stack (Phase 5)

SELF-DEPLOYED STAND-IN. Not a real asset, not a third-party protocol. Deployed
because task 0.4 established no RWA-linked instrument is live on X Layer testnet.
See docs/decisions/ADR-009-rwa-standin.md.

| contract | address | role |
|---|---|---|
| RwaVault | `0x3BF12df3BB0b6f0dF8c57089ab78e402bf698F84` | oracle mark, issuer pause, redemption window, yield index |
| RwaRiskGuard | `0x401Ef3E4b9b838A021109c3BBebb7FDC70Cb9278` | RiskGuard plus four RWA-specific refusals |

RWA market id: `0xb87ddfac6c6e92e03338f4740cb958f7966abe0a7c132510824697e5994bacba`

- vault: https://www.oklink.com/x-layer-testnet/address/0x3BF12df3BB0b6f0dF8c57089ab78e402bf698F84
- rwa guard: https://www.oklink.com/x-layer-testnet/address/0x401Ef3E4b9b838A021109c3BBebb7FDC70Cb9278

Policy on chain: maxOracleAge 3600s, windowBuffer 43200s, maxDivergence 300 bps,
gross cap 1000e18, RWA market cap 400e18.
