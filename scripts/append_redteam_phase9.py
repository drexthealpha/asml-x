"""Append the browser-measured results to the Phase 9 red team evidence."""

OUT = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/phase9/phase9-redteam.md"

SECTION = """

## Measured in the Browser pane

### Readability, at 1920x1080 and 390x844

The contrast gate passes at BOTH sizes, all five views:

```
view      chars   smallest font   worst ratio   % below AA
1 YOU      2450        12px          8.28:1         0
2 DECIDE  10000        12px          8.28:1         0
3 RISK     7269        12px          8.28:1         0
4 CHAIN    7337        12px          8.28:1         0
5 RWA      4185        12px          8.28:1         0
```

WCAG AA is 4.5:1 for normal text. The worst character on any view is 8.28:1, which is nearly double
the threshold, and the median is 10.5:1. **Zero characters below AA.**

### Clipping, at 1920x1080

```
view      clippedText  clippingBoxes  collapsedCells  hOverflow  mainClipsBy  underflow
1 YOU          0             0              0             0           0           0
2 DECIDE       0             0              0             0           0           0
3 RISK        42             0              0             0           0           0
4 CHAIN        0             0              0             0           0           0
5 RWA          0             0              0             0           0           0
```

`pass: true`. Zero clipping containers, zero collapsed cells, zero horizontal page overflow, and
`main` clips by 0. RISK reports 42 clipped text nodes inside a scroll region that can reach them,
which is the gate's own tolerated case rather than unreachable content.

### Clipping, at 390x844: THIS FAILS

```
view      clippedText  clippingBoxes
1 YOU          0             3
2 DECIDE      29             4
3 RISK        59             3
4 CHAIN       56             7
5 RWA         43             1
```

`pass: false`. The four views built in Phase 4 lay out through `ResizablePanelGroup`, which arranges
panels horizontally regardless of viewport width, so at 390px panels cannot shrink below their
content and text is clipped inside them.

**This is measured by the project's OWN Phase 4 gate, `scripts/measure-overflow.js`, not by an
instrument written for this task.** That matters, because an earlier version of a Phase 9 audit
reported a far larger mobile catastrophe that turned out to be its own false positives (ADR-018).
This smaller failure is real and survives that correction.

Per ADR-018 the frontend gate is scoped to desktop viewports, with the narrow-viewport failure named
here rather than hidden behind a threshold. The product must not be described as responsive or
mobile-ready anywhere in the README or JUDGE-GUIDE.

## A hostile user clicks everything twice

53 enabled controls, every one double-clicked in sequence as fast as the DOM allows:

```
page still rendered:      yes
exit controls still there: yes
content did not collapse:  yes
uncaught errors:           none
```

The demo button is separately guarded server-side: `POST /demo` holds an atomic and returns 429 with
"a demo cycle is already running, wait for the current cycle to finish, then press again". Two
overlapping `asml run` processes would submit from the same key and collide on the nonce, and the
second failure would look like a broken agent rather than a double-click. A judge will double-click.

## GATE

| check | result |
|---|---|
| zero uncited frontend files | PASS, 0 of 14 components uncited |
| zero characters below WCAG AA | PASS, worst 8.28:1 against a 4.5:1 floor, both viewports |
| zero clipping containers, desktop | PASS at 1920x1080 |
| zero clipping containers, 390px | **FAIL**, named above and scoped by ADR-018 |
| hostile double-clicking | PASS, 53 controls, no crash, no blank |

**GATE: PASS at desktop viewports, with the narrow-viewport clipping recorded as a known defect
rather than resolved.**
"""


def main():
    with open(OUT, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(SECTION)
    print(f"appended to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
