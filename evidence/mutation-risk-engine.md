# Mutation gate: risk engine

Task 2.1.8, standing rule R7. Captured 2026-08-09 06:33:28 UTC.

Method: break the exact thing a test guards, confirm the suite goes RED,
restore, confirm GREEN. A mutation that stays GREEN proves the limit has
no real test, and that test is then deleted or rewritten.

| # | mutation | expected | result |
|---|---|---|---|
| 1 | order notional: > becomes >= | RED | RED, test holds |
| 2 | order notional: invert to < | RED | RED, test holds |
| 3 | market notional: invert | RED | RED, test holds |
| 4 | gross notional: invert | RED | RED, test holds |
| 5 | net skew: invert | RED | RED, test holds |
| 6 | free margin: invert | RED | RED, test holds |
| 7 | mark staleness: invert | RED | RED, test holds |
| 8 | rate limit: invert | RED | RED, test holds |
| 9 | daily loss kill: invert comparison | RED | RED, test holds |
| 10 | consecutive losses kill: invert | RED | RED, test holds |
| 11 | manual kill switch: neutralise | RED | RED, test holds |
| 12 | data stale kill: neutralise | RED | RED, test holds |
| 13 | non-positive size guard: neutralise | RED | RED, test holds |
| 14 | fixed-point scale: drop MICRO divisor in notional | RED | RED, test holds |

## Task 2.1.4: compile-time bypass proof

Status: DEMONSTRATED. Forging a `RiskApproved` from the executor crate
fails to build. Full compiler output: evidence/bypass-compile-error.txt

```
error[E0308]: mismatched types
error: could not compile `executor` (lib) due to 1 previous error
```

This is why the guarantee is architectural rather than procedural: an
agent that tries to skip the risk gate does not fail a runtime check, it
fails to compile. The workspace also forbids unsafe_code, so there is no
transmute escape.

## Summary

- mutations that correctly went RED: 14
- mutations that stayed GREEN or were inconclusive: 0
