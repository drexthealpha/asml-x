# Layout: ported from HypeTerminal instead of hand-rolled

Correction to tasks 4.1 and 5.x. The previous layout was my own invention wearing citations from
their code. This replaces the invented parts with theirs.

## The measured defect

At a 632px viewport, scanning every element in the document:

| view | `main` clientHeight | `main` scrollHeight | elements past the viewport | clipping containers |
|---|---|---|---|---|
| Decide | 466 | **2480** | 646 | 2 |
| Risk | 466 | **6945** | 683 | 2 |
| Chain | 466 | **2298** | 284 | 1 |

`main` carried `overflow-hidden`, so a container holding 6,945px of content in 466px of box was not
scrollable. Roughly 93% of the Risk view was **unreachable**, not merely awkward.

Cause: `flex-wrap` on the workspace, so the sidebar dropped below the main column at narrow widths and
the stack exceeded the fixed height. That is not a HypeTerminal pattern. It is mine.

A second, quieter defect: the journal's ACTION column rendered **empty**. Its grid is
`3rem 5.5rem 1fr 4rem 3rem 5rem`, whose fixed tracks total 20.5rem = 328px, already wider than the
~300px panel. The `1fr` action column resolved to zero and the most important field in the row
disappeared with no visual sign that anything was missing.

## What was ported

`ui-v2/src/components/resizable.tsx` is their `apps/terminal/src/components/ui/resizable.tsx`, a thin
wrapper over `react-resizable-panels`, pinned to **4.6.0** because that is the version they pin rather
than the 4.12.2 latest. Structure, `data-slot` attributes, aria-orientation handling and the
`withHandle` grip are theirs unchanged; only the colour utilities are rewritten against this project's
CSS variables, because this project wires tokens as variables rather than through their layer-3
`@theme` colour mapping.

Their workspace shape, from `apps/terminal/src/components/trade/layout/main-workspace.tsx`, now
applied here:

- root `flex-1 min-h-0 flex flex-col`, chrome `shrink-0`
- body height `max(calc(100dvh - chrome), floor)` (theirs is `max(calc(100dvh - 9.375rem), minPx)` at
  lines 28-30). A short viewport makes the body TALLER than the screen and the page scrolls, which is
  what makes clipping impossible by construction.
- resizable panels side by side, each with a `minSize` so a drag cannot collapse one to nothing
- **no wrapping anywhere.** For a strip that cannot shrink they use `overflow-x-auto`
  (`main-workspace.tsx:41`), so the wide tables here now carry a min-width and scroll sideways with
  every column intact.

## After

`bash scripts/serve-ui.sh`, then `scripts/measure-overflow.js` in the console. **`pass: true` at both
widths tested:**

| viewport | view | main clips by | horizontal page overflow | clipping containers | collapsed columns |
|---|---|---|---|---|---|
| 1280x720 | Decide | **0** | **0** | **0** | **0** |
| 1280x720 | Risk | **0** | **0** | **0** | **0** |
| 1280x720 | Chain | **0** | **0** | **0** | **0** |
| 640x600 | Decide | **0** | **0** | **0** | **0** |
| 640x600 | Risk | **0** | **0** | **0** | **0** |
| 640x600 | Chain | **0** | **0** | **0** | **0** |

640x600 is the width that produced the 6,945px clip and the missing ACTION column, so it is the width
worth re-testing rather than a comfortable one.

The remaining `clippedText` counts (90, 74, 47) are INTENTIONAL truncation: `text-overflow: ellipsis`
with the full value in a `title` attribute. The scan excludes those explicitly rather than counting a
design decision as a defect, and that exclusion is in the script so the number cannot be quietly
improved by widening the definition later.

### Three more defects the second scan found

The first fix created two of them, which is the argument for re-measuring after every change rather
than after the last one.

1. **Sticky headers clipped.** Giving the header row and the row spacer the same `min-width` left the
   header as a SIBLING of the scroller, so it overflowed the panel body and was cut off while the rows
   scrolled underneath: measured `clientW 379 / scrollW 477` and `clientW 416 / scrollW 832`. Worse
   than being cut off, the two would drift out of horizontal alignment, putting a numeric column under
   the wrong label. Header and rows now share one scroller with the header `sticky top-0`.
2. **The contracts ADDRESS column collapsed to 10.9px** while holding a 42-character address. A
   contracts table without addresses is a list of names.
3. **A duplicate `style` attribute** from running a patch script twice, which TypeScript caught as
   `JSX elements cannot have multiple attributes with the same name`.

The operator can also drag the split between columns now, which a terminal user expects and which no
amount of tuning my flex-basis numbers would have given.

## The wider lesson

The study document had 30+ correct citations into their code and the layout still did not follow them.
Citing a pattern is not applying it. Three things were invented where theirs were available on disk at
`/home/zulab/hypeterminal`:

1. the type scale and greys (`evidence/phase5/readability.md`)
2. the workspace layout (this file)
3. the wrap-instead-of-scroll response to narrow widths

Reproduce the scan: serve `ui-v2`, open the console, and run the overflow scan in
`scripts/measure-overflow.js`.
