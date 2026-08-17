# Task 9.5: Pause and Withdraw always visible

Run 2026-08-16. Measured in the Browser pane against the build in `ui-v2/dist`, provider per ADR-016.

## The design decision

The task says the controls must be "visible on every screen of the personal view"; its PASS condition
says "in the DOM and visible at every ROUTE". The stricter reading is the one built. Pause and
Withdraw live in the CHROME, above the view switch, so all five routes inherit them. A user with
money in the vault who is reading the Risk tab does not have to navigate anywhere to get out.

`ui-v2/src/components/exit-bar.tsx`. It renders nothing when there is no position: a bar that is
always present but usually disabled trains people to ignore it, and it would occupy chrome height on
the landing screen where task 9.2 measures the primary action's position.

## What "visible" means here

The task's counter asks for a bounding-rect assertion. That is necessary and not sufficient, so the
audit requires all four of:

1. the bounding rect lies entirely inside the viewport
2. non-zero area
3. computed `display`, `visibility` and `opacity` do not hide it
4. **`elementFromPoint` at the control's centre lands on the control or a descendant**

Check 4 is the one a rect test cannot do. A button sitting inside the viewport with an overlay
painted on top of it passes every geometric check and is completely unclickable.

## Results

Every route reached by clicking its real tab button, not by setting state.

### 1280x720

```
route      bar   withdraw inside/reachable   pause inside/reachable
1 You      yes   true / true                 true / true
2 Decide   yes   true / true                 true / true
3 Risk     yes   true / true                 true / true
4 Chain    yes   true / true                 true / true
5 RWA      yes   true / true                 true / true

withdraw rect  left 1104  top 70  100x22     elementFromPoint -> button
pause    rect  left 1212  top 70   60x22     elementFromPoint -> button
```

### 390x844

```
route      bar   withdraw inside/reachable   pause inside/reachable
1 You      yes   true / true                 true / true
2 Decide   yes   true / true                 true / true
3 Risk     yes   true / true                 true / true
4 Chain    yes   true / true                 true / true
5 RWA      yes   true / true                 true / true
```

Ten route-and-viewport combinations, all passing.

## Page integrity around the controls

A control can be perfectly placed on a page falling apart around it, so the audit also measures
whole-page text overlap and horizontal overflow at every route:

| viewport | overlaps | overflow |
|---|---|---|
| 1920x1080 | 0 | 0 |
| 1280x720 | 0 | 0 |
| 390x844 | 1 | 0 |

The single remaining item is on the RWA route at 390px, where a block number and an order
description collide in the comparator panel. Recorded as a defect for task 9.10's frontend gate.

## Two real defects this task exposed

**1. The exit bar overflowed its own bar at 390px.** It is `h-7` (28px) and the Withdraw button
rendered 38px because its label wrapped to two lines, pushing content into the tab strip above. Fixed
by hiding the descriptive label and the balance readout below 640px (both are duplicated inside the
personal view, so nothing is lost) and by giving the buttons `whitespace-nowrap leading-none` so a
one-line bar cannot contain a two-line control.

**2. Two components were polling the chain independently, and it hid the exit control.** `Activate`
and `ExitBar` each read the position with seven `eth_call`s every five seconds. Fourteen calls per
five seconds from one page was enough for X Layer's public RPC to start refusing connections, and
since both components swallow read failures by design, nothing surfaced an error: the exit bar simply
never appeared. A control a user needs in a panic, missing, on a page that looked healthy.

Fixed architecturally rather than by lengthening the interval: `ui-v2/src/lib/position-store.ts` runs
ONE poll with one set of subscribers and an in-flight guard so a slow response cannot overlap the next
tick. A third consumer now costs nothing.

## THE AUDIT ITSELF WAS WRONG, AND THAT IS THE MOST IMPORTANT ENTRY HERE

The first version of the page-integrity check reported catastrophic numbers: 463 overlaps and 1382
overflowing elements at 390x844, and 185 overlaps at 1280x720. On that basis a mobile-layout
emergency was escalated to the user and a scope decision was requested.

**Those numbers were produced by the instrument, not the page.** Two false-positive classes, both
mine:

- **Scroll clipping ignored.** `getBoundingClientRect` is viewport-relative and knows nothing about
  an ancestor's `overflow: auto`. Rows scrolled out of a journal list still report full rects, and
  they were being compared against elements genuinely on screen.
- **Overflow measured on raw rects.** A wide table inside an `overflow-x: auto` container correctly
  reports a rect past the viewport edge while being properly contained and scrollable. That is the
  pattern this project's own rules prescribe for wide content, and it was being flagged as a defect.

Both checks now intersect an element's rect with the client rect of every clipping ancestor and use
the PAINTED result; an element clipped to nothing is skipped entirely. After the fix the same pages
measure 0, 0 and 1.

ADR-018 records the withdrawal in full. The rule that follows from it: **inspect a sample of
individual findings before reporting a count as a defect.** Four samples would have caught this in a
minute. Two earlier gates in this phase UNDER-reported and let defects through; this one
OVER-reported, which wasted more time and produced a false emergency. A number from an unchecked
instrument is not evidence, including an instrument I wrote.

## GATE: PASS

Both controls present, inside the viewport, and confirmed reachable by hit test on all five routes at
both 1280x720 and 390x844.
