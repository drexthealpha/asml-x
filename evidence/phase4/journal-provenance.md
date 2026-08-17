# The journal WAS stale, and one JUDGE-GUIDE claim rested on it

**RESOLVED 2026-08-12.** The agent was run for 40 cycles with the current binary, writing 43 rows
with 39 submitted transactions and 280 real limit refusals whose numbers are in micro-units. The 87
pre-fix rows were SPLIT OUT to `evidence/journal-legacy-2026-08-09.jsonl` and are not deleted:
they are a real record of real decisions, and the split boundary was verified by auditing each half
(`evidence/phase4/journal-split.txt`, every wei-scaled value on the legacy side, none on the current
side). `bash scripts/77-journal-scale-audit.sh` now reports PASS.

Consequences that followed from the same run: the risk panel draws a real utilisation bar
(`MarketNotionalTooLarge 52.96 / 50.00 100%`), ink coverage went from 46.63% to 59.83% with no
layout change, and the largest empty rectangle fell from 8.10% to 5.92%
(`evidence/phase4/density-measured.md`).

The finding below is kept verbatim, because the mechanism it describes is the lesson: a fix that
does not regenerate its artifacts leaves the artifacts asserting the bug.

---


Found while building the risk panel (task 4.5), which reads utilisation back out of the refusal
strings the engine actually emitted. Recorded here before the panel was finished, because the
panel would otherwise have rendered these numbers as if they were current.

## What the data says

`evidence/journal.jsonl`, last written **2026-08-09**, 87 rows. Every one of the 40
`OrderNotionalTooLarge` refusals in it carries numbers like:

```
risk refused: OrderNotionalTooLarge { got: 3000000000000000000000000000000, limit: 25000000 }
candidate label: take order 0 Buy 1500000000000.000000 base at 2000000000000.000000
```

`got` is 3e30 against a 25e6 limit. Reproduce the count:

```bash
bash scripts/77-journal-scale-audit.sh
```

Result: **0 refusals with a plausible `got`, 40 with a `got` above 1e12.**

## What that means

`1500000000000.000000 base` is 1.5e18 in raw micro-units. `WEI_PER_MICRO` is 1e12, so this is a
wei value that was never divided down: the size and price in those candidates are exactly 1e12
times too large. The refusal itself was correct (the engine refused, which is its job), but the
NUMBER attached to it is meaningless.

## The current code does not have this bug

`crates/market-intel/src/lib.rs:95-110` converts at the boundary, with the reason in a comment:

```rust
// Normalised to micro-units at the boundary, so nothing downstream ever
// sees an 18-decimal number. See WEI_PER_MICRO.
size_base: wei_to_micro(...),
price_quote: wei_to_micro(...),
```

So this is not a live defect. It is a stale artifact: the journal was written on 9 Aug by a binary
built before that conversion was added, and it has been the file every downstream claim reads
since.

## The claim that is affected, and what happens to it

`JUDGE-GUIDE.md` step 2 says:

> In the recorded run `OrderNotionalTooLarge` appears 40 times, meaning the engine wanted to trade
> larger and was refused.

The count is real. The interpretation is wrong. The engine did not want to trade "larger"; it
generated candidates 1e12 times too large because of a units bug that has since been fixed, and
refused them. A judge who checked that sentence against the numbers in the journal would find a
`got` of 3e30 and reasonably conclude the risk numbers are fabricated.

Actions, in order:

1. This file, so the finding exists before anything is rewritten. **Done.**
2. `scripts/77-journal-scale-audit.sh`, so the anomaly is detectable by command rather than by
   reading. **Done.**
3. The UI refuses to render a utilisation bar from a refusal whose `got/limit` ratio is
   implausible, and says why in the panel. A bar reading 1.2e25% would be worse than no bar.
   **Done**, in `ui-v2/src/components/risk-panel.tsx`.
4. Regenerate the journal with the CURRENT binary (`asml observe`), so every panel reads
   post-fix data. Then the numbers in the risk panel are real utilisations and the JUDGE-GUIDE
   sentence becomes true as written.
5. Until step 4 lands, the JUDGE-GUIDE sentence is corrected rather than left standing.

## Why this is worth its own file

The v1 build recorded "18-vs-6 decimal mismatch" as a FIXED error. It was fixed in the code and
not in the evidence, and the evidence is what every claim points at. A fix that does not
regenerate its artifacts leaves the artifacts asserting the bug.
