# Phase 17 gate report: docs and JUDGE-GUIDE

Run 2026-08-16 20:27:18 UTC. Verdict: **PASS**

## 17.1 JUDGE-GUIDE, rewritten for the conviction bar

Restructured to lead with **the mainnet proof and the user flow**, not the formal verification.
Step 1 is "it is live on mainnet with the user's own money" and step 2 is "a person can
deposit, let the agent trade, and get their money back". Formal verification and the
differential proof moved to step 3, where they belong: they are what makes the product safe to
use, not the reason to look at it.

It also carries a section named **The fastest way to attack this submission**, listing the four
places a hostile reader should look first, in order, including one I would want cut if found.

## 17.2 README leads with what a person can do

The first sentence is now the product, not the architecture. The old opening led with
"an autonomous market brain" and, more seriously, still said **Testnet only**, which stopped
being true in Phase 12.

## 17.3 limitations.md updated

Four entries were **stale in a flattering-or-misleading direction** and are corrected:

1. "No realized PnL anywhere" is no longer true. It is replaced by the measured result, which
   is worse: a 40% hit rate on n=10 and a net position that lost. **The failure to be
   profitable is now measured rather than merely unmeasured**, which is a stronger disclosure.
2. "No mainnet deployment" is struck through rather than deleted, so the change is visible.
3. The coordination burst stall is marked FIXED, with the WRONG diagnosis kept because that is
   the useful part: per-socket timeouts could not have worked, since a deadline on a socket
   does not shorten a queue.
4. "No run demo button" and "codebase-memory-mcp and paperscraper never installed" were both
   false.

AggLayer is now explicitly listed under what is NOT claimed.

## 17.4 every claim carries a resolvable tag

Checked in **both** directions across six judge-facing documents: every `[C-xxx]` resolves to
a row, and every script those documents tell a reader to run exists. **0 dangling tags, 0
missing scripts**, against 119 claim ids.

Backward matters as much as forward: Phase 16 found two chain rows citing scripts that never
existed, and a guide that sends a judge to a missing script fails at the worst possible moment.

## 17.5 density and consistency on the final build

Ink coverage **28.50% to 38.13%**, largest void **14.17% to 13.50%**, by moving the MAINNET
panel onto the landing surface. Detail and two measurement traps in
[evidence/phase17/density.md](../phase17/density.md).

`scripts/144-claim-consistency.sh` now passes **fully**, closing the outstanding half of task
12.7. It had been reporting JUDGE-GUIDE as a missing file for six phases because it looked in
`docs/` while the guide lives at the repo root, and it correctly refused to call that a pass.

## Reproduce

```
python3 scripts/187-claim-tags.py
bash scripts/144-claim-consistency.sh
```
