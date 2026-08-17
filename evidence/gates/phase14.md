# Phase 14 gate report: formal and learning residue

Run 2026-08-16 19:16:32 UTC. Verdict: **PASS**

| check | result |
|---|---|
| cited files present and non-empty | 1 of 1, 0 missing |
| C-14xx chain rows | 9 |
| workspace tests | 115 passed, 0 failed |
| claim-to-artefact drift | 0 |

## What each subtask established

| task | claim | shown able to fail by |
|---|---|---|
| 14.1 | one cap rule agrees across the live contract, revm and the Rust engine, on the revert SELECTOR and decoded arguments | the under-cap call succeeding, without which a contract that reverted on everything would pass |
| 14.2 | 8 invariants hold over a 128-run depth-64 campaign | removing the free-balance guard turns exactly one invariant red, the right one |
| 14.3 | one decision traced through the real OpenTelemetry SDK | the SDK's own exporter output is captured; the JSON alone could not distinguish wired from linked |
| 14.4 | the loop closes in money, not only direction | inverting the PnL sign turns 3 tests red |
| 14.5 | ADR-011's falsification test run, not deferred | it ANSWERS against the ADR's author, finding no margin |
| 14.6 | the learning effect with its sample size | removing the source makes 4 figures report ERROR, not zero |

## Independent recomputation

Every settlement's realized PnL was recomputed in Python from the row's own persisted fields
and compared to what the Rust engine wrote. **Rows failing to reproduce: 0.** This is the
same idea as 14.1: two implementations agreeing on the numbers, not on a boolean.

## WHAT PHASE 14 DOES NOT ESTABLISH

The part a hostile reader should go to first, stated here rather than left to be found.

1. **No profitability claim exists, and none is possible from this data.** The realized PnL is
   mark to market against a later observed mid, not cash from a closing trade. Ten settled
   outcomes is not a track record.
2. **The mid moves because this project moves it.** The venue is a self-deployed stand-in with
   a static book, so nothing settles on its own. The profit labels in 14.5 are INDUCED by
   `scripts/171-build-pnl-sample.sh`, which means a river win would not have licensed
   reopening ADR-011 either. The benchmark's own file says so above its numbers.
3. **The agent's hit rate is below a coin flip.** Not hidden: it is on the landing page in the
   loss colour. What is claimed is that the loop measures outcomes and responds to them, which
   it demonstrably did by cutting momentum weight from 2000 to 391 until the agent stopped
   taking positions at all.
4. **The trace exports to stdout, not to a collector.** ADR-019 records that the OTLP-over-gRPC
   exporter is a few lines away and is not shipped only because there is no collector to point
   it at.
5. **AggLayer settlement remains INFERRED**, unchanged by this phase and still not asserted
   anywhere as verified.

## A claim withdrawn during this phase

ADR-019 originally rejected the OpenTelemetry SDK on the ground that crates.io was unreachable
from this machine. That was never tested and was false: `index.crates.io` and
`static.crates.io` both return 200 and `cargo add` resolved first try. The ADR now records the
correction rather than the conclusion it wrongly supported. This is the second time an ADR in
this project has been rewritten against its author, after ADR-018.

## A file destroyed and rebuilt, recorded rather than hidden

`ui-v2/src/components/learning-panel.tsx` was overwritten while adding 14.6's panel, because it
was written without reading the existing file of that name first. It was untracked, so no copy
existed in git or in any session transcript, and it was REBUILT against the props `App.tsx`
passes rather than recovered. It renders correctly against live data, verified in the browser.
The rebuild is stated in the file's own header. An audit that quietly omitted this would be
worth less than no audit.

## Reproduce

```
bash scripts/164-differential-proof.sh      # 14.1
bash scripts/166-vault-invariants.sh        # 14.2
bash scripts/165-decision-trace.sh          # 14.3
bash scripts/168-realized-pnl.sh            # 14.4
bash scripts/169-settle-with-real-move.sh   # 14.4, non-zero settlement
bash scripts/172-river-profit-target.sh     # 14.5
bash scripts/174-learning-effect.sh         # 14.6
bash scripts/176-phase14-audit.sh           # 14.7, this file
```
