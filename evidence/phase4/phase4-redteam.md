# Phase 4 adversarial audit

Task 4.9. The instruction is to try to make the UI display a number that is not in the journal, and
to feed it a malformed journal. PASS is that every malformed input produces a visible error state
and never a plausible number.

Stage the fixtures and serve them:

```bash
bash scripts/80-ui-redteam.sh
cd /home/zulab/redteam-check && python3 -m http.server 4175 --bind 127.0.0.1
```

## The seven attacks, each one a way a dashboard usually lies

| # | attack | what it would prove if it worked |
|---|---|---|
| 1 | a truncated JSON line | the writer was interrupted and the reader hid it |
| 2 | valid JSON, every field the wrong type (`decision_id` a string, `signals` null, `candidates` a string) | the parser coerces instead of rejecting |
| 3 | a row with no `decision_id` | valid JSON is treated as a usable decision |
| 4 | absurd magnitudes: a `1e30` score, `999999999` bps confidence, a 20-digit block number | impossible values render as data |
| 5 | one GOOD row at the end | bad rows are dropped and the screen looks fine, hiding the loss |
| 6 | `learned-state.json` that is not JSON | a parse failure becomes an empty panel |
| 7 | `deployments.json` served as HTML, what a dev server returns for a missing file | HTML is parsed as "successfully nothing" |

Attack 5 is the one that matters most. Dropping bad rows silently and rendering the good one is the
failure a reader cannot detect, because the result looks exactly like a working dashboard.

## First run: TWO REAL FAILURES

Recorded because they are the output of the exercise.

**Failure A, attack 4 succeeded.** The journal row rendered:

```
4   100000000000000000000   take order 9 Buy 1e30 base   10000000.0%
```

A 20-digit block number and a confidence of ten million percent, both presented as ordinary data
with a percent sign attached. Basis points are hundredths of a percent, so 999999999 bps is not a
percentage at all, and a number past `Number.MAX_SAFE_INTEGER` printed as digits is a rounding
artifact rather than the value in the file.

**Failure B.** The "Agent transactions" panel showed "Waiting for a decision that submitted a
transaction" while `deployments.json` was unreadable, which reads as a normal state.

## Fixes

Domain validation in `ui-v2/src/lib/data.ts`, applied at parse time, per row:

- `blockNumber` must be finite, non-negative, and within exact integer range.
- `thesisConfidenceBps` must be within 0..10000, because that is what basis points mean.
- Candidate scores and signal values past exact integer range are flagged.

Each violation is recorded on the row as an `anomalies` entry. Display guards enforce it:

- `bpsToPct` returns `"invalid"` outside 0..10000 instead of dividing by 100 anyway.
- `fromMicro` returns `"invalid"` past exact integer range.
- `blockLabel` returns `"invalid"` past exact integer range.
- The journal row marks the flagged row with `[!]` and colours the block cell red.
- The brain panel lists the specific violations at the top of the panel.
- The top bar counts them separately from malformed lines, because a well-formed file with wrong
  data is a different problem from a broken file.

A row with anomalies still RENDERS. Hiding it would be attack 5 succeeding by my own hand.

## Second run: PASS

Measured in the page, not judged by eye:

```
header:    "3 malformed line(s)   1 row(s) out of range"
journal:   "5 38000000 hold 50.0%"          <- the good row
           "4 invalid [!] take order 9 Buy 1e30 base   invalid"   <- the absurd row, flagged
digits of 13+ characters anywhere on screen: 0
"10000000.0%" or any 999999 figure:          absent
"NaN", "undefined", "Infinity":              absent
```

Panel outcomes:

| panel | outcome |
|---|---|
| Live brain | renders the good row, lists the out-of-range violations for the flagged one |
| Decision journal | 2 rows of 5 lines, the flagged row marked `[!]` with `invalid` in place of impossible values |
| Risk | no utilisation bar drawn, states that no refusal carried usable numbers |
| Contracts on chain | `Source unavailable. data/deployments.json` server returned HTML, file not present |
| Learning | `Source unavailable. data/learned-state.json` Expected property name or '}' in JSON at position 31 |
| Agent transactions | names `data/journal.jsonl` when no decisions load |

Three of five malformed lines are reported as malformed, one is reported as out of range, and one
good row renders. Nothing on screen is a number that is not in the file.

## The no-data proof still passes after these changes

Re-checked against the same build, because a fix in one direction can break the other:

```
numeric cells containing a digit: 1  ("poll 4s", a static config value)
cells rendering an em dash:      14
panels naming their source:      7/7
```

Full write-up of that check: `evidence/phase4/nodata-proof.md`.
