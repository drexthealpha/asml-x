# RWA layer on X Layer mainnet

Run 2026-08-18 01:15:47 UTC. Chain **196**.

The RWA refusal layer is this project's differentiator and the hackathon runs a separate
AI-RWA track. Until this run it existed only on testnet 1952, so a judge checking mainnet for
that track would have found the core product live and the RWA angle absent.

| contract | address | bytecode |
|---|---|---|
| RwaVault | `0x9B3fd14D7f5f843edd8977196026EFBE98Eede2b` | 4055 chars |
| RwaRiskGuard | `0x5311C01f6BcFFd78F0C42EC88cce4eba658CD4Ed` | 12423 chars |

Market id `0xb87ddfac6c6e92e03338f4740cb958f7966abe0a7c132510824697e5994bacba`.

## Read back from chain

These are read from chain 196 after the deploy, not from the file this script wrote:

```
RwaVault.oraclePrice()          1000000000000000000    (1.0)
RwaVault.paused()               false
RwaRiskGuard.maxPerMarket()     400000000000000000000  (400e18)
RwaRiskGuard.maxDivergenceBps() 300                    (3.00%)
```

## What the RWA layer adds

Four refusals that only mean anything for an instrument backed by something off-chain: a stale
oracle, a paused issuer, a redemption window, and divergence between the oracle and the market.
A crypto-only risk engine has no reason to check any of them.

## Reproduce

```
bash scripts/209-deploy-rwa-mainnet.sh
```
