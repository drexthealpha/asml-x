# Docs audit

R5 sweep, captured 2026-08-09 18:59:03 UTC.

| claim | documented | measured | result |
|---|---|---|---|
| rust test suites green | 19 | 19 | MATCH |
| foundry tests passing | 50 | 50 | MATCH |
| mutation-risk-engine | claimed all RED | 14 RED, 0 gaps, 0 inapplicable | CLEAN |
| mutation-contracts | claimed all RED | 15 RED, 0 gaps, 0 inapplicable | CLEAN |
| mutation-rwa | claimed all RED | 18 RED, 0 gaps, 0 inapplicable | CLEAN |
| mutation-learning | claimed all RED | 12 RED, 0 gaps, 0 inapplicable | CLEAN |
| README venue | 0x7092050F3C... | present | MATCH |
| README riskGuard | 0xE64b6e937F... | present | MATCH |
| README batchExecutor | 0x81beCFdE5a... | present | MATCH |
| README rwaVault | 0x3BF12df3BB... | present | MATCH |
| README rwaRiskGuard | 0x401Ef3E4b9... | present | MATCH |
| all doc file links | resolve | resolve | MATCH |
| judge-facing docs | no em dashes | none found | MATCH |
| README evidence labels | present | 9 lines carry a label | INFO |

## Result

All checked claims match. 0 mismatches.
