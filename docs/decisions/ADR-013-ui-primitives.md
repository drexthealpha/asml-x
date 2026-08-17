# ADR-013: shadcn primitives, HypeTerminal density

Task 3.6. Status: ACCEPTED. Date: 2026-08-11.

THINKING: #13 dialectical (two mandates that appear to conflict, and the resolution is not a
compromise between them), #27 opportunity-cost (a component library is days of work either way,
so the question is which days buy more), #30 trade-off.

## The conflict

The product spec mandates shadcn/ui. HypeTerminal's `packages/ui` is Base UI + CVA, 42 files and
5,681 lines, and it is the reference this project was told to study for density.

## The decision

**shadcn as the primitive layer. HypeTerminal for density, tokens, spacing and data patterns.**

The two mandates only conflict if "study HypeTerminal" is read as "copy HypeTerminal's
components". It is not what makes their terminal good. What makes it good is in
`evidence/ui-study.md`: a 40-line layout constants file, a two-layer token architecture, a type
scale shifted one step down from Tailwind's default, `tabular-nums` on every numeric cell, row
counts derived from measured height, and updates batched to animation frames. None of that is
coupled to Base UI. All of it survives a change of primitive library.

## What is taken, and where it lands

Twelve patterns, listed in `evidence/ui-study.md` section 5 with `path:line` citations. The four
that matter most:

1. **Layout as constants.** `ui-v2/src/config/layout.ts` mirrors
   `apps/terminal/src/config/layout.ts:3-19`, including the idea at
   `config/layout.ts:12` of a separate smaller minimum height for a disconnected panel. This
   project's equivalent of "disconnected" is "no journal rows yet", and the same answer applies.
2. **Two-layer tokens.** Primitives in `@theme`, semantics under `:root` and `.dark`, per
   `packages/ui/src/globals.css:25-107` and `:110-260`. shadcn already expects CSS variables, so
   this is the layer where the two systems meet rather than fight.
3. **The shifted type scale.** `text-2xs` at 12px/16px for data rows
   (`packages/ui/src/globals.css:42-45`). shadcn's defaults are one step larger throughout, and
   a rebuild on default sizes cannot reach terminal density regardless of padding. Overriding the
   scale is a token change, not a component change.
4. **Height-derived row counts.** `use-orderbook-rows.ts:3-26`. The row count is a data
   parameter, not a CSS overflow, which is why their panels have no dead space at the bottom.

## What is not taken, with the reason for each

- **`packages/ui` itself.** Base UI + CVA is a different primitive layer, and mixing two would
  mean two focus-management implementations and two dialog stacks. The spec picked shadcn; that
  decision stands.
- **The WebSocket transport.** `packages/hl-react/src/internal/websocket/` is 1,031 lines of
  subscription lifecycle, reconnect backoff and payload guards. X Layer testnet gives us JSON-RPC
  over HTTP, so there is no socket to keep alive. Two ideas from it do transfer, because the
  underlying problems are ours too: `batch-updater.ts:15-56` (a block-driven poll produces the
  same burst-of-updates problem) and `staleness.ts:20-109` (stale data is already a kill-switch
  condition in `crates/risk-engine`, so a UI that cannot show staleness would be showing less
  than the agent knows).
- **TanStack Start SSR.** `ui-v2` is a Vite SPA. Their own terminal route disables SSR
  (`apps/terminal/src/routes/perp.tsx:7` sets `ssr: false`), which is the strongest available
  evidence that the SSR layer buys little for a page like this.
- **Lingui i18n.** One locale. The `t\`\`` macros are throughout their components and would be
  pure overhead here.
- **`react-resizable-panels`.** Adopted only if a draggable split is actually needed. The
  constants describing the splits are useful either way, and they are the part being copied.

## The failure conditions this is meant to prevent

Stated as defects, from the frontend gate: a generic AI-dashboard layout, empty regions, oversized
cards holding three numbers each, unadapted default shadcn, placeholder charts, fake data.

"Unadapted default shadcn" is the one this ADR is most exposed to, since it mandates shadcn. The
concrete defence is that the token layer is replaced before any component is generated: the type
scale, the 4px spacing base, the `--radius-factor: 0.5` (`globals.css:78-79`), and the three-shadow
palette (`globals.case:90-92`) all land first. A shadcn card rendered against those tokens is not
a default shadcn card. If a reviewer can tell which component library was used by looking at the
spacing, this decision failed.

## Falsification test

Mechanical, and it runs in task 3.8: every file under `ui-v2/src/` must cite a pattern from
`evidence/ui-study.md`. A frontend file with no citation is the signal that the study stopped
being used and the defaults took over.
