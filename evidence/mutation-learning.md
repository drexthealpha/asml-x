# Mutation gate: the learning layer

Phase 7, standing rule R7. Captured 2026-08-09 16:40:45 UTC.

| # | file | mutation | result |
|---|---|---|---|
| 1 | lib.rs | momentum weight severed from the decision (parameter never read) | RED, test holds |
| 2 | lib.rs | dead band removed, so a flat market scores every forecast wrong | RED, test holds |
| 3 | lib.rs | dead band made enormous, so nothing is ever scored | RED, test holds |
| 4 | lib.rs | settle lag ignored, so a forecast is scored against its own price | RED, test holds |
| 5 | lib.rs | direction scoring inverted | RED, test holds |
| 6 | lib.rs | minimum sample guard removed, learning from noise | RED, test holds |
| 7 | lib.rs | momentum weight upper clamp removed | RED, test holds |
| 8 | lib.rs | weight update sign inverted, so a good signal loses weight | RED, test holds |
| 9 | lib.rs | holds are scored instead of dropped | RED, test holds |
| 10 | lib.rs | pending forecasts no longer persisted | RED, test holds |
| 11 | lib.rs | learned params no longer persisted | RED, test holds |
| 12 | lib.rs | param change loses its sample-count attribution | RED, test holds |
