# Phase 5 red team: the one-candidate journal

Task 5.7. PASS as written: "single-candidate cycles are visibly flagged as defects".

## The attack, and why it is the right one

Every claim this terminal makes rests on one thing: the agent SCORED alternatives and rejected them.
The brain panel's argument is "look at the 52 candidates it refused". So the sharpest attack is not
malformed data, it is **plausible data that quietly removes the reasoning**.

An if-else ladder, journalled honestly, produces exactly one candidate per cycle: the action it was
always going to take, with a score attached afterwards. If this UI renders that in the same style as a
53-candidate decision, it is vouching for reasoning it cannot see, and every screenshot of it becomes
a claim the data does not support.

Two fixtures, in one file so both appear together:

| attack | rows | what it simulates |
|---|---|---|
| exactly ONE candidate, the chosen one | 35 of 43 | a hardcoded action with a score attached after the fact |
| ZERO candidates | 8 of 43 | an action recorded with no reasoning at all |

Built by `bash scripts/92-phase5-redteam.sh` from the real journal, so every other field stays
realistic: real blocks, real transaction hashes, real thesis text. Only the candidate list is
attacked. Served at `http://localhost:4177` from `/home/zulab/redteam5`, never staged into
`ui-v2/public/data`.

## Result: flagged, at every level

Measured in the live page:

| check | result |
|---|---|
| header out-of-range counter | **43 of 43 rows** |
| journal rows carrying the `[!]` marker | **25 of 25 mounted** |
| brain panel flag block present | **yes** |
| brain text, one-candidate row | `only 1 candidate: a cycle that scored one option did not choose, it executed a fixed action` |
| brain text, zero-candidate row | `no candidates recorded: this row shows an action with no reasoning behind it` |
| brain header candidate count on a zero row | `0 cand` |

The two cases produce **different sentences**, because they are different defects. One candidate means
the cycle did not choose. Zero means there is no record of reasoning at all, which is worse, and
collapsing them into one warning would hide that.

## Where the check lives, and why that matters

In `ui-v2/src/lib/data.ts`, inside `decisionAnomalies`, which is the same function that already
catches an impossible confidence or a block number beyond exact integer range. It is in the **data
layer, not a panel**, so every surface inherits it: the journal row marker, the header counter, and
the brain panel's flag block all come from one computation. A check implemented per-panel would have
been three chances to forget one.

It also means the flag cannot be bypassed by looking at a different view.

## What this does NOT prove

It does not prove the real agent scores alternatives. It proves the UI refuses to present a
one-candidate cycle as a decision. The evidence that the real agent scores alternatives is the live
journal itself: **2,279 candidates across 43 decisions, 2,236 of them refused**, with the losing
scores and reasons in the refusal ledger.

The two together are the argument: the agent produces reasoning, and the UI would have said so if it
had not.

## Reproduce

```bash
bash scripts/92-phase5-redteam.sh
# then open http://localhost:4177 and check the header counter and any journal row
```
