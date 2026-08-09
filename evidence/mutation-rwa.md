# Mutation gate: the RWA layer

Task 5.2.3, standing rule R7. Captured 2026-08-09 12:22:02 UTC.

| # | layer | mutation | result |
|---|---|---|---|
| 1 | onchain | pause refusal neutralised | RED, test holds |
| 2 | onchain | oracle staleness refusal neutralised | RED, test holds |
| 3 | onchain | window buffer refusal neutralised | RED, test holds |
| 4 | onchain | divergence refusal neutralised | RED, test holds |
| 5 | onchain | reduce gains an RWA block (breaks the asymmetry) | RED, test holds |
| 6 | onchain | setRwaPolicy loses onlyOwner | RED, test holds |
| 7 | onchain | divergence made one-sided | RED, test holds |
| 8 | onchain | yield index allowed to decrease | RED, test holds |
| 9 | onchain | oracle timestamp not refreshed on price set | RED, test holds |
| 10 | onchain | onlyIssuer removed from setPaused | RED, test holds |
| 11 | offchain | missing RWA state defaults to healthy instead of failing closed | RED, test holds |
| 12 | offchain | pause refusal removed | RED, test holds |
| 13 | offchain | oracle staleness comparison inverted | RED, test holds |
| 14 | offchain | window buffer drops the untilWindow > 0 guard | RED, test holds |
| 15 | offchain | divergence comparison inverted | RED, test holds |
| 16 | offchain | RWA checks applied to every instrument kind, not just RWA | RED, test holds |
| 17 | offchain | reduce exemption removed, so exits get blocked | RED, test holds |
| 18 | offchain | is_reducing always true, so RWA checks never run | RED, test holds |

## Summary

- RED (good): 18
- gaps or inconclusive: 0
