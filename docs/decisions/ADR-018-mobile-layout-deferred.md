# ADR-018: the narrow-viewport report was an instrument error

Status: SUPERSEDES ITS OWN FIRST DRAFT, 2026-08-16. The deferral decision this ADR originally
recorded was taken on numbers that were wrong.

## What the first draft of this ADR claimed

That the app was broken at 390x844 on every legacy route, with these measurements:

| route | overlapping text pairs | elements past the right edge |
|---|---|---|
| 1 You | 20 | 0 |
| 2 Decide | 196 | 456 |
| 3 Risk | 119 | 377 |
| 4 Chain | 118 | 244 |
| 5 RWA | 10 | 305 |

It attributed the cause to `ResizablePanelGroup` laying panels out horizontally regardless of
viewport width, proposed a vertical-stack rewrite below `MOBILE_BREAKPOINT_PX`, and the user was
asked to choose between fixing it now, declaring the product desktop-only, or deferring. They chose
to defer.

## What was actually true

**Almost every one of those numbers was produced by my own measuring instrument, not by the page.**

The detector had two false-positive classes, and both were mine:

1. **Scroll clipping was ignored.** `getBoundingClientRect` is viewport-relative and knows nothing
   about an ancestor's `overflow: auto`. Rows scrolled out of a journal list still reported full
   rects, and those phantom rects were compared against elements that really were on screen. At
   1920x1080 this alone manufactured 78 overlaps; every pair inspected sat at the bottom edge of one
   scrolling list.

2. **Horizontal overflow was measured on raw rects.** A wide table inside an `overflow-x: auto`
   container correctly reports a rect past the viewport edge while being perfectly contained and
   scrollable. That is the pattern this project's own rules PRESCRIBE for wide content, and the
   detector was flagging it as a defect. That produced all 355 "overflowing" elements at 1280x720
   and all 1382 at 390x844.

Both checks now intersect an element's rect with the client rect of every clipping ancestor and use
the resulting PAINTED rect. An element clipped to nothing is skipped, because something not painted
cannot collide with anything.

## The measurements after fixing the instrument

| viewport | overlaps | overflow |
|---|---|---|
| 1920x1080 | 0 | 0 |
| 1280x720 | 0 | 0 |
| 390x844 | **1** | 0 |

The single remaining item is on the RWA route at 390px: a block number and an order description
colliding in the comparator panel.

## Decision

**There is nothing here to defer.** The premise of the deferral has been withdrawn. The narrow
viewport is not broken; it has one layout defect on one route, which is ordinary work rather than a
scope question, and it is fixed as part of task 9.10's frontend gate rather than escalated.

The `ResizablePanelGroup` rewrite proposed by the first draft is NOT undertaken. It was a fix for a
problem that did not exist, and it would have invalidated every density and overflow measurement
Phase 4 recorded.

## The lesson, which is the part worth keeping

This is the third time in Phase 9 that a gate reported something false, and the first two were
under-reporting: task 9.2's audit passed a page whose tab strip painted over itself, and task 9.5's
rect-only audit passed an exit bar overlapping the tabs. Both were fixed by adding checks.

This one is the opposite failure and it is more dangerous. An audit that under-reports lets a defect
through. An audit that OVER-reports burns real time chasing defects that do not exist, and here it
went further: it escalated a false emergency to the user and extracted a scope decision on numbers
that were an artifact of my own code.

The rule that follows: **before reporting a measurement as a defect, inspect a sample of the
individual findings and confirm each one is real.** Four samples would have caught this in a minute.
I ran the count and reported it. A number produced by an instrument nobody has checked is not
evidence, and that applies to instruments I wrote as much as to any other.
