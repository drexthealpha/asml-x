# HypeTerminal study

Tasks 3.2 through 3.6. This document is the FRONTEND GATE: no component, layout, chart or table
is written in `ui-v2/` until this file exists with specific, checkable citations. Every frontend
file added later must name the pattern here that it applies.

**Source studied:** github.com/vipineth/hypeterminal at commit
`a61992eda0fa269ea38d64dd50ed133db1236052` (2026-08-08). Cloned to `/home/zulab/hypeterminal`,
outside this repository, because it is a reference to read rather than a dependency to ship.
Structure map with per-file line counts: `evidence/hypeterminal/file-tree.txt`. Regenerate with
`bash scripts/73-clone-hypeterminal.sh`.

**Scale:** `apps/terminal` is 517 source files and 70,389 lines; `packages/hl-react` is 53 files
and 4,526 lines; `packages/ui` is 42 files and 5,681 lines. Every citation below is
`path:line` against that commit, so any claim here can be checked against the actual file.

**One independent confirmation of a decision already made:** their
`apps/terminal/package.json` pins `"@tanstack/react-table": "8.21.3"`, the exact version this
build pinned in task 1.15 while v9.1.2 is current. A production terminal on the same version is
better evidence for that pin than the reasoning that produced it.

---

## 1. Layout and density (task 3.2)

### The layout is CONFIGURATION, not CSS scattered through components

`apps/terminal/src/config/layout.ts` is 40 lines and holds the entire spatial system as
constants. This is the single most transferable idea in the repository, and it is transferable
without adopting one line of their component code.

- `apps/terminal/src/config/layout.ts:3-19` `PANEL_LAYOUT`: three named panel groups, each with
  `defaultSize` as a percentage AND a `minSize`. `MAIN` splits 77% analysis / 23% sidebar with
  minima 50% and 18%. `MARKET` splits 76% chart / 24% orderbook with minima 40% and 20%.
- `apps/terminal/src/config/layout.ts:10-14` the `ANALYSIS` group carries `minHeightPx: 660`,
  `chart.minHeightPx: 260`, `positions.minHeightPx: 400`, and separately
  `positions.disconnectedMinHeightPx: 180`. That last constant is the detail worth stealing: the
  positions panel reserves LESS height when the user is not connected, because there is nothing
  to show. It is a direct, deliberate answer to "what fills this region when there is no data",
  which is one of the named failure conditions for this project's UI.
- `apps/terminal/src/config/layout.ts:32-40` chrome heights are Tailwind classes held as
  constants: header `h-11` (2.75rem), footer `h-8`, banner `h-8`, and a precomputed combined
  offset `pt-[4.75rem]` with the arithmetic written in a comment. Nothing recomputes these
  inline.
- `apps/terminal/src/config/layout.ts:1` `MOBILE_BREAKPOINT_PX = 768`, a single numeric
  breakpoint rather than a set of media queries spread across files.
- `apps/terminal/src/config/layout.ts:29-30` `TOKEN_SELECTOR_ROW_HEIGHT_PX = 48` with
  `TOKEN_SELECTOR_OVERSCAN = 10`, which is virtualiser configuration living next to the layout
  rather than inside the component.

### How empty space is prevented

- `apps/terminal/src/components/trade/layout/main-workspace.tsx:26`
  `const marketBodyHeight = "max(calc(100dvh - 9.375rem), ${marketBodyMinHeightPx}px)"`. The
  workspace is sized from the VIEWPORT minus the chrome, with a floor. It never sizes to content,
  which is what produces the dead regions this project is explicitly told to avoid.
- `apps/terminal/src/components/trade/layout/main-workspace.tsx:28-30` a child reports its
  desired height upward (`onDesiredHeightChange`) and the parent takes
  `Math.max(PANEL_LAYOUT.ANALYSIS.minHeightPx, ...)`. Panels negotiate height instead of
  guessing.
- `apps/terminal/src/components/trade/layout/main-workspace.tsx:36,45,48` the recurring class
  triple is `flex-1 min-h-0 flex flex-col` plus `shrink-0` on chrome. `min-h-0` on every flex
  child is what allows an inner scroll region to actually scroll instead of expanding its parent.
  It appears on nearly every container in the tree.
- `apps/terminal/src/components/trade/orderbook/orderbook-panel.tsx:87` the panel root is
  `h-full min-h-0 flex flex-col overflow-hidden bg-surface`, and
  `orderbook-panel.tsx:102` the tab content is `flex-1 min-h-0 mt-0 pt-0 flex flex-col`. Note
  `mt-0 pt-0`: the panel strips the primitive's default spacing rather than living with it.

### Padding scale actually used

Read off the panels rather than off a style guide: `px-2 py-1.5` for headers
(`orderbook-panel.tsx:104`), `py-0.5 px-2` for data rows
(`orderbook-row.tsx:34`), `gap-1` between columns, `mx-2.5 my-1` for a vertical divider
(`main-workspace.tsx:41`). The vertical rhythm on a data row is **2px of padding**. That is the
density target, and it is achieved by padding, not by font size.

---

## 2. Tokens and typography (task 3.3)

Source: `packages/ui/src/globals.css`, 429 lines. Values copied, not paraphrased.

### Two-layer token architecture

- `packages/ui/src/globals.css:25-107` Layer 1, primitives inside `@theme`. Tailwind v4's
  CSS-first configuration: there is no `tailwind.config.js`.
- `packages/ui/src/globals.css:110-199` Layer 2, semantic tokens under `:root` for light.
- `packages/ui/src/globals.css:200-260` the `.dark` block redefines the same semantic names.

Components reference `--bg-raised` or `--text-error`, never `--color-grey-solid-850`. Swapping a
palette therefore touches one layer. This is the structure `ui-v2` copies.

### Type scale, with the numbers

`packages/ui/src/globals.css:42-57`. Each size ships with its line height:

| token | size | line height |
|---|---|---|
| `--text-2xs` | 12px | 16px |
| `--text-xs` | 14px | 20px |
| `--text-sm` | 16px | 24px |
| `--text-base` | 20px | 28px |
| `--text-lg` | 24px | 32px |

The terminal's data rows use `text-2xs`, which is **12px/16px**
(`orderbook-row.tsx:34`, `orderbook-panel.tsx:104`). Their `text-sm` is 16px, i.e. the whole
scale is shifted one step down from Tailwind's default. A rebuild that uses default Tailwind
sizes cannot reach this density no matter how the padding is tuned.

- `packages/ui/src/globals.css:28-29` fonts: `"Inter Variable"` for sans,
  `ui-monospace, "SF Mono", monospace` for mono.
- **`tabular-nums` on every numeric cell**: `orderbook-row.tsx:34`,
  `orderbook-panel.tsx:109`. Without fixed-width digits a price column jitters on every update,
  which is the single most obvious tell of an amateur trading UI.
- `packages/ui/src/globals.css:65-71` spacing base is `--spacing: 4px`, a 4px grid, with the
  Figma-to-Tailwind mapping written into the comment.
- `packages/ui/src/globals.css:76-87` radii are computed:
  `--radius-8: calc(8px * var(--radius-factor))` with `--radius-factor: 0.5`. One variable
  changes the roundness of the entire product. Their factor is 0.5, i.e. deliberately tighter
  than the token names suggest.
- `packages/ui/src/globals.css:90-92` only three shadows exist, one of them an inset. A terminal
  separates regions with 1px strokes, not elevation.
- `packages/ui/src/globals.css:95-96` `--tracking-uppercase: 2px`, applied to the uppercase
  column headers (`orderbook-panel.tsx:104` uses `uppercase tracking-wider`).
- `packages/ui/src/globals.css:99-105` a five-step z-index scale, sticky 40 through toast 1200.
- `packages/ui/src/globals.css:11-19` a `hover` custom variant gated on `@media (hover: hover)`,
  so touch devices do not get stuck hover states. Two lines that fix a real mobile defect.

### Depth bars and the colour maths

`apps/terminal/src/styles.css:506-517`:

```css
.depth-bar-ask { background: linear-gradient(90deg, transparent 0%, oklch(from var(--text-error) l c h / 0.18) 100%); }
.depth-bar-bid { background: linear-gradient(90deg, oklch(from var(--text-success) l c h / 0.18) 0%, transparent 100%); }
.dark .depth-bar-ask { /* same, 0.25 */ }
```

`oklch(from var(--x) l c h / alpha)` derives a transparent variant from an existing token instead
of hardcoding a second colour. Dark mode raises alpha from 0.18 to 0.25 because the same
translucency reads weaker on a dark background. Bid fills left-to-right, ask right-to-left, so
the two sides mirror around the spread.

---

## 3. Data layer (task 3.4)

Source: `packages/hl-react/src/internal/websocket/`, 1,031 lines across nine files. This is the
part that makes a terminal feel fast, and it is almost entirely mechanism this project can reuse
conceptually even though our transport is JSON-RPC polling rather than a WebSocket.

### Every reliability number is one constant table

`packages/hl-react/src/internal/websocket/reliability.ts:1-48` is a single
`WS_RELIABILITY_LIMITS` object holding reconnect backoff, payload caps, subscription limits and
staleness thresholds:

- `reliability.ts:2-7` reconnect: `baseDelayMs: 250`, `maxDelayMs: 5000`,
  `maxAttemptsBeforeCooldown: 20`, `cooldownMs: 30000`.
- `reliability.ts:8-14` a SECOND backoff for the SDK's own reconnecting socket, 500ms to 30s,
  with a comment naming the two files that import it so the two loops cannot drift apart.
- `reliability.ts:19-28` payload size caps PER METHOD: 256KB default, but 1MB for `l2Book` and
  384KB for `trades`. A payload guard with one global limit is either too tight for the book or
  too loose for everything else.
- `reliability.ts:32-47` staleness thresholds per method: 20s for market streams
  (`l2Book`, `trades`, `allMids`), 60s for user streams (`orderUpdates`, `webData2`). Market
  data is expected to be continuous; user data is not.
- `reliability.ts:51-58` methods are CLASSIFIED (`USER_STREAM_METHODS`, `KNOWN_METHODS`) and an
  unknown method falls through to market-stream behaviour with a one-shot dev warning, so a new
  SDK method cannot silently land on the wrong path.

### Updates are batched to animation frames

`packages/hl-react/src/internal/websocket/batch-updater.ts:15-56`. `createBatchedUpdater`
buffers items and flushes once per `requestAnimationFrame`
(`batch-updater.ts:9-13` falls back to a 16ms timeout where rAF is absent).
`add` schedules at most one frame (`batch-updater.ts:20-21` returns early if a frame is already
pending); `flush` cancels the pending frame and drains synchronously; `destroy` drops the buffer.
A book that ticks 200 times a second still renders 60 times a second.

### Staleness is a watchdog, not a per-component timer

`packages/hl-react/src/internal/websocket/staleness.ts:20-109`. One interval
(`checkIntervalMs: 5000`) walks a `Map` of keys, each with its own `thresholdMs`, `lastMessageAt`
and listener set (`staleness.ts:3-8`), and notifies only the subscribers of keys that changed
state. `markFresh` on each message, `isStale` for reads. N subscriptions cost one timer.

### Hidden tabs stop costing anything

`packages/hl-react/src/internal/websocket/visibility.ts:13,26,46-47,57,77`. A single
`document.hidden` observer with a listener set, plus a `resume` event listener for mobile.
Market streams pause and buffer while hidden; user streams stay live. A terminal left open in a
background tab is the normal case, not an edge case.

### Health is derived and surfaced

`packages/hl-react/src/internal/websocket/health.ts:148-294`. `createHealthReport` reduces the
store into metrics (`health.ts:161` max reconnect attempts, `health.ts:164` count of stale
subscriptions) and emits graded findings: a `reconnect-storm` WARNING at half the cooldown
threshold (`health.ts:64,222-228`) escalating at the threshold itself
(`health.ts:214-220`), and a stale-stream finding at `health.ts:280`. The connection's health is
a first-class object with severities, not a green dot.

### Render isolation, three mechanisms stacked

1. `orderbook-panel.tsx:44` `useDeferredValue(orderbook)`. The incoming snapshot is deferred, so
   a burst of updates cannot block input.
2. `orderbook-panel.tsx:52-66` every derived value is memoised: `processLevels` per side,
   `getMaxTotal`, and a manually reversed asks array (`orderbook-panel.tsx:60-65`) written as an
   index loop rather than `[...asks].reverse()`.
3. `orderbook-row.tsx:52-65` `memo(OrderbookRowComponent, areEqual)` with a HAND-WRITTEN
   comparator over eight scalar fields. Rows are compared by value, so a new snapshot object
   re-renders only the rows whose numbers actually moved.

And the measurement to go with it: `orderbook-panel.tsx:17` `useRenderCommitTrack("orderbook")`
instruments the panel's commits. They measure render cost rather than assuming it.

---

## 4. Order book and charts (task 3.5)

### The row count is computed from available height

`apps/terminal/src/components/trade/orderbook/use-orderbook-rows.ts`, 32 lines, and the cleanest
answer to "how many rows should this panel show" I have read:

- `use-orderbook-rows.ts:3-5` `ROW_HEIGHT = 19`, `MIN_ROWS_PER_SIDE = 3`,
  `MAX_ROWS_PER_SIDE = 20`.
- `use-orderbook-rows.ts:16-20` measure `clientHeight`, subtract the measured height of the
  spread strip (found by `[data-slot='orderbook-spread']`), halve the remainder, divide by
  `ROW_HEIGHT`, then clamp between the minimum and the maximum.
- `use-orderbook-rows.ts:25-26` a `ResizeObserver` recomputes on every resize and is disconnected
  on cleanup.
- `orderbook-panel.tsx:52-56` `visibleRows` is passed INTO `processLevels`, so the row count is a
  data-fetching parameter, not a CSS overflow. The panel never renders rows it will clip.

This is the mechanism that keeps the book flush to its container at any window size, and it is
why the layout has no dead space at the bottom of a panel. Note `ROW_HEIGHT = 19` is asserted,
not measured per row: 12px text with 16px line height plus `py-0.5` (2px) is 18-19px.

### Depth bar rendering

`orderbook-row.tsx:18` `depthPct = maxTotal > 0 ? (level.total / maxTotal) * 100 : 0`, guarded
against a zero denominator. `orderbook-row.tsx:29-33` the bar is an absolutely positioned sibling
with `inset-y-0` and `pointer-events-none`, anchored to the right for asks and the left for bids
via a computed style key, with the text layer above it at `relative z-10`
(`orderbook-row.tsx:34`). One div, no canvas, no per-row gradient definition.

### Price grouping is user-controlled and feeds the subscription

`orderbook-panel.tsx:26-38` builds grouping options from the mark price, then the SELECTED
grouping becomes part of the subscription parameters (`nSigFigs`, `mantissa`) at
`orderbook-panel.tsx:31-38`. Grouping happens server-side, not by re-bucketing in the client.
`orderbook-panel.tsx:106-118` puts the grouping dropdown INSIDE the "Price" column header rather
than in a toolbar, which costs zero vertical space.

### Unit toggle in the column header

`orderbook-panel.tsx:121-137` the "Size" and "Total" headers are buttons that toggle
base/quote display, showing the active unit in parentheses. `orderbook-row.tsx:21-25` does the
conversion (`size * price`) and switches to 2 decimals when showing quote. Controls live in the
labels they affect.

### Empty and error states are specific

`orderbook-panel.tsx:151-153` distinguishes "Failed to load order book." from "Waiting for order
book...". `orderbook-panel.tsx:76` `hasData = orderbookStatus !== "error"`. Two different
sentences for two different situations, in the panel body where the data would have been.

### Chart integration

`apps/terminal/src/routes/perp.tsx:6-10` the route sets `ssr: false` for the terminal page: the
chart cannot server-render, so the route says so declaratively.
`main-workspace.tsx:15-16,57-62` the analysis section and the trade sidebar are lazy components
mounted inside `Suspense` and `ClientOnly` with skeleton fallbacks. The chart library is heavy;
it is code-split and client-only, and the fallback is a skeleton with the right dimensions rather
than a spinner.

---

## 5. What transfers, and what does not (task 3.6)

The full decision is ADR-013. Summary, because it governs every Phase 4 task:

**Transfers, and will be cited by name in `ui-v2/`:**

1. Layout as a constants file (`config/layout.ts`), including a disconnected-state minimum
   height.
2. The two-layer token architecture: primitives in `@theme`, semantics in `:root` and `.dark`.
3. The shifted type scale: 12px/16px `text-2xs` for data rows, with `tabular-nums` on every
   numeric cell.
4. `flex-1 min-h-0 flex flex-col` on containers, `shrink-0` on chrome, viewport-derived heights.
5. Height-derived row counts with a `ResizeObserver`, passed into the data layer.
6. Depth bars as an absolutely positioned gradient sibling, colour derived with `oklch(from ...)`.
7. Batched updates flushed on `requestAnimationFrame`.
8. A single reliability-constants table with per-stream thresholds.
9. A staleness watchdog on one interval with per-key thresholds.
10. `memo` with a hand-written comparator on the hot row component.
11. Controls inside column headers rather than in a toolbar.
12. Distinct empty and error sentences in the panel body.

**Does not transfer:**

- `packages/ui` itself (Base UI + CVA). This project uses shadcn primitives, per the product
  spec. Their component library is not copied; their density and tokens are.
- The WebSocket transport. X Layer testnet gives us JSON-RPC over HTTP, so subscriptions,
  reconnect backoff and payload guards have no direct analogue. The BATCHING and STALENESS ideas
  do transfer: our block-driven poll produces the same "burst of updates" problem, and stale data
  is already a kill-switch condition in the risk engine.
- TanStack Start SSR. `ui-v2` is a Vite SPA. Their own terminal route disables SSR anyway
  (`perp.tsx:7`), which is evidence that the SSR layer buys little for this kind of page.
- Lingui i18n (`t\`\`` macros throughout). One locale, no translation layer.
- `react-resizable-panels`. Adopted only if a resizable split is actually needed; the constants
  that describe the splits are useful regardless.

## Citation count, counted rather than estimated

**70 `path:line` citations, 0 invalid, across 20 distinct files**, all pinned to commit
`a61992ed`. The gate's threshold is thirty.

Those numbers come from `bash scripts/74-verify-ui-study.sh`, which resolves every citation
against the clone and fails on any that points at a missing file or past the end of a file. The
first run reported 43 invalid, all of them short-form filenames the resolver could not find; the
resolver now falls back to a unique-basename lookup and refuses ambiguous ones. Audit output:
`evidence/hypeterminal/citation-audit.txt`.

I originally wrote "fifty-one citations across six files" in this section from memory of writing
it. The real numbers are above. What the audit cannot check is whether each cited line says what
the surrounding sentence claims: that still needs a reader. It can and does catch a citation
pointing at nothing, which is the failure that would make this document worthless.
