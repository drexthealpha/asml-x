# Task 9.2: the landing surface

Run 2026-08-15. Build served from `ui-v2/dist` at `http://localhost:4173`, measured in the Browser
pane at two viewport sizes. Provider: the real key-backed EIP-1193 provider per ADR-016, present so
the surface renders its connected-capable state rather than the no-wallet branch.

## The decision that makes this a landing surface

The personal view is the **first tab and the default**, not a fifth tab appended after the existing
four. Task 9.2's named fake win is "a beautiful landing page that hides the product behind a second
click", and its counter is that 9.4's click counter starts from this screen. A cold visitor is
already on it, so the count starts at zero rather than at one.

`view-tabs.tsx` VIEWS order: **You**, Decide, Risk, Chain, RWA. `App.tsx` defaults to `"you"`.

## Measurements

Harness: `scripts/landing_audit.js`, evaluated in the page. Bounding rects are only meaningful in a
real layout engine at a real viewport, so nothing here is inferred from source.

### 1280x720

```
primary action        wallet-connect  "Connect wallet"
  rect                top 135  left 21  bottom 169  right 355  (334x34)
  fully inside        true
blocking empty states 0
text overlaps         0
horizontal overflow   0 elements past the right edge
empty below content   0.6% of viewport height
value proposition     1 sentence
```

### 390x844

```
primary action        wallet-connect  "Connect wallet"
  rect                top 243  left 21  bottom 277  right 369  (348x34)
  fully inside        true
blocking empty states 0
text overlaps         0
horizontal overflow   0 elements past the right edge
empty below content   0.2% of viewport height
value proposition     1 sentence
```

Value proposition, one sentence, present at both sizes:

> An agent that trades your capital under limits it cannot exceed, and that you can pause or exit at
> any time.

## THE AUDIT PASSED A BROKEN LAYOUT ON ITS FIRST RUN

Worth recording in full, because the failure was in the gate rather than in the page, and a gate that
cannot see a defect will certify it.

The first version of `landing_audit.js` measured two things: the primary action's bounding rect, and
full-screen overlays that intercept pointer events. Both were fine at 390x844, so it reported PASS.
A screenshot taken immediately afterwards showed the tab strip's hint text painting **on top of** the
last tab: "5 RWA" and "press 1 to 5" occupying the same pixels.

Neither of the original checks can express that. Three were added, each measuring something the
screenshot showed:

| check | what it catches | why it is always a defect |
|---|---|---|
| text overlap | two text-bearing elements whose rects intersect by more than 2px, excluding ancestors | overlapping text is never a style choice |
| emptiness | viewport fraction below the last painted content | "empty regions above baseline" is a named failure condition for this project |
| horizontal overflow | any element extending past the right edge | horizontal scroll by another name |

Re-run with the stronger audit, the defect was reported as a **539 px-squared overlap between "5RWA"
and "press 1 to 5"**, which is the number the fix had to move to zero.

### The fix

At 390px the five tabs consume the whole row, the `flex-1` hint container collapses to zero width,
and `truncate` does not save it: the text paints over the last tab. Both the hint and the keyboard
helper are now `hidden md:flex`. The keyboard helper is doubly pointless on a touch device, where
there is no keyboard to press 1 to 5 on. `md:` is 768px, the same breakpoint HypeTerminal pins as
`MOBILE_BREAKPOINT_PX` in `config/layout.ts:1`.

Desktop was re-measured after the fix to confirm the hint is still shown there and nothing regressed:
overlaps 0, hint element present.

## GATE: PASS

Zero blocking empty states, zero text overlaps, zero horizontal overflow, and the primary action's
bounding rect fully inside the viewport at both 1280x720 and 390x844.
