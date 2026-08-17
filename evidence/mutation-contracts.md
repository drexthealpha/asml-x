# Mutation gate: contracts

Task 2.2.4, standing rule R7. Captured 2026-08-12 03:14:57 UTC.

| # | mutation | result |
|---|---|---|
| 1 | market cap check removed | RED, test holds |
| 2 | market cap: > to >= | RED, test holds |
| 3 | gross cap check removed | RED, test holds |
| 4 | notKilled removed from addExposure | sed did not apply |
| 5 | revive becomes agent-callable | RED, test holds |
| 6 | setMarketCap loses onlyOwner | RED, test holds |
| 7 | unconfigured market no longer fails closed | RED, test holds |
| 8 | gross accounting drifts from parts | RED, test holds |
| 9 | reduce underflow guard removed | RED, test holds |
| 10 | overfill guard removed | RED, test holds |
| 11 | fill accounting not recorded | RED, test holds |
| 12 | price scale divisor dropped in take | RED, test holds |
| 13 | sell escrow skipped at post | **STAYED GREEN, TEST GAP** |
| 14 | cancel refund skipped | sed did not apply |
| 15 | only-maker cancel check removed | RED, test holds |

## Summary

- RED (good): 12
- gaps or inconclusive: 3
