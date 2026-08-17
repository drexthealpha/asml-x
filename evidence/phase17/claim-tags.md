# Task 17.4: claim tags, checked in both directions

Chain holds **126** claim ids.

| document | tags cited | dangling | scripts referenced |
|---|---|---|---|
| `JUDGE-GUIDE.md` | 17 distinct tags | 0 | 6 |
| `README.md` | 15 distinct tags | 0 | 9 |
| `docs/limitations.md` | 7 distinct tags | 0 | 0 |
| `docs/COORDINATION-PROTOCOL.md` | 0 distinct tags | 0 | 1 |
| `docs/invariants.md` | 0 distinct tags | 0 | 8 |
| `docs/mainnet-path.md` | 1 distinct tags | 0 | 1 |

## Why both directions

**Forward:** every `[C-xxx]` must resolve to a row. A dangling tag is worse than no tag,
because it looks like evidence and is not.

**Backward:** every script a judge-facing document tells a reader to run must exist. A guide
that sends a judge to a missing script fails at the worst possible moment. Phase 16 found two
chain rows citing scripts that never existed, which is the same defect one layer down.

## Result

**No dangling tags and no missing scripts.** Every claim tag in every judge-facing
document resolves to a row in the chain, and every script those documents name is present.

## Reproduce

```
python3 scripts/187-claim-tags.py
```
