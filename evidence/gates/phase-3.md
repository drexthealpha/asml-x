# Phase 3 gate: the HypeTerminal study

**The non-cuttable gate.** No frontend code existed until `evidence/ui-study.md` did. Between task
1.15 (which installed the toolchain) and Phase 4 (which built the panels), `ui-v2/src/main.tsx` held
a three-line placeholder whose text named the gate, so shipping it by accident would have been
obvious rather than plausible.

## What was studied

github.com/vipineth/hypeterminal at commit `a61992eda0fa269ea38d64dd50ed133db1236052`, cloned to
`/home/zulab/hypeterminal`, **outside** the product repo, because it is a reference to read rather
than a dependency to ship.

Scale, measured rather than described: `apps/terminal` is 517 source files and 70,389 lines,
`packages/hl-react` 53 files and 4,526 lines, `packages/ui` 42 files and 5,681 lines. The map with
per-file line counts is `evidence/hypeterminal/file-tree.txt`, and it exists specifically so the
study could cite `file:line` instead of describing an impression.

## The output

`evidence/ui-study.md`: **70 `path:line` citations across 20 distinct files, zero invalid.**

The count is not asserted. `scripts/74-verify-ui-study.sh` resolves every citation against the clone
and fails on any that names a missing file or reaches past the end of one. Its first run reported
**43 invalid** (short-form filenames the resolver could not find); the resolver now falls back to a
unique-basename lookup and refuses ambiguous ones. Audit output:
`evidence/hypeterminal/citation-audit.txt`.

I had also written "fifty-one citations across six files" in the document from memory of writing it.
The audit corrected that to 70 across 20. A study whose own summary is wrong by 40% is the small
version of the failure this phase exists to prevent.

## What the study found that a README skim would not

Five things, each with a citation and each now in `ui-v2`:

1. **Layout is a 40-line constants file** (`apps/terminal/src/config/layout.ts:1-40`), not sizes
   scattered through components. It includes `positions.disconnectedMinHeightPx: 180` beside
   `positions.minHeightPx: 400` (`config/layout.ts:12`): a panel reserves LESS height when there is
   nothing to show. That single constant is a direct answer to "what fills this region when there is
   no data", which is a named failure condition for this project.
2. **The type scale is shifted one step down from stock Tailwind** (`packages/ui/src/globals.css:42-57`).
   Their `text-2xs` is 12px/16px and their `text-sm` is 16px. Data rows use `text-2xs`. A rebuild on
   default Tailwind sizes cannot reach terminal density no matter how the padding is tuned, which is
   the kind of thing you only learn by reading the token file.
3. **Row counts are derived from measured height and passed into the DATA layer**
   (`use-orderbook-rows.ts:3-26`, consumed at `orderbook-panel.tsx:52-56`). The panel never renders
   rows it will clip, which is why their panels have no dead strip at the bottom.
4. **Updates are batched to one animation frame** (`batch-updater.ts:15-56`) and staleness is one
   watchdog with per-key thresholds (`staleness.ts:20-109`), not a timer per component. Their
   reliability numbers all live in a single table (`reliability.ts:1-48`) with per-stream thresholds:
   20s for market data, 60s for user streams.
5. **`memo` with a hand-written comparator on the hot row** (`orderbook-row.tsx:52-65`), plus
   `useDeferredValue` on the incoming snapshot (`orderbook-panel.tsx:44`) and
   `useRenderCommitTrack` (`orderbook-panel.tsx:17`) to measure the result rather than assume it.

One independent confirmation of a decision made earlier: their `apps/terminal/package.json` pins
`@tanstack/react-table` at **8.21.3**, exactly the version task 1.15 pinned while 9.1.2 is current.

## The conflict, resolved

The product spec mandates shadcn/ui. HypeTerminal's `packages/ui` is Base UI + CVA. ADR-013 resolves
it: shadcn as the primitive layer, HypeTerminal for density, tokens, spacing and data patterns. The
two mandates only conflict if "study HypeTerminal" is read as "copy its components", and what makes
their terminal good is not coupled to Base UI.

Twelve patterns transfer, five do not, each with a reason:
`docs/decisions/ADR-013-ui-primitives.md`.

Not taken, and why: `packages/ui` itself (different primitive layer), the WebSocket transport (we
poll JSON-RPC, though the batching and staleness IDEAS transfer because the problems are ours too),
TanStack Start SSR (their own terminal route sets `ssr: false` at `routes/perp.tsx:7`), Lingui i18n
(one locale), and `react-resizable-panels` (only if a draggable split earns it).

## Reproduce

```bash
bash scripts/73-clone-hypeterminal.sh   # clone at the pinned commit, map it with line counts
bash scripts/74-verify-ui-study.sh      # resolve all 70 citations, fail on any that points at nothing
```

## Gate status

**OPEN.** `evidence/ui-study.md` exists with 70 verified citations against a threshold of 30. Every
file added in Phase 4 names the pattern it applies in a header comment, and task 3.8 keeps that
checkable.
