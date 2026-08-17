# Task 17.5: density on the final build

Measured in the Browser pane at 1920x1080 with `scripts/measure-density.js`, on the built
`dist/`, not on a dev server.

| metric | before | after | note |
|---|---|---|---|
| ink coverage | 28.50% | **38.13%** | text-run coverage of the viewport |
| text runs | 167 | **236** | |
| numeric cells | 42 | **66** | `.num` elements |
| largest empty rect | 408x720, 14.17% | **648x432, 13.50%** | |

## What was wrong and what was done

The left column ended below "Your position", leaving a **408x720 void, 14.17% of the viewport**.
That is the same proportion an earlier phase treated as a defect after measuring a 624x472 hole,
and the fix then was the same principle as now: **fill a void with data the project already holds,
never with decoration.**

The MAINNET panel was moved onto the landing surface. It was previously reachable only from the
CHAIN tab, which meant a judge who read the landing page and left would never have seen that this
runs on X Layer mainnet with real money. It is the strongest evidence in the submission and it was
one click away from being missed.

## A measurement trap, recorded

The first re-measurement returned **numbers identical to the baseline**, including an unchanged text
run count. The browser was serving a stale bundle: `index-45Nw93sF.js` while the build had produced
`index-ChCly-7j.js`. Identical numbers after a real change are a signal to check the instrument, not
to conclude the change did nothing.

A screenshot then showed the app occupying roughly a third of the frame with the rest black, which
looks exactly like a broken layout. It is not: `document.body` and `#root` both measure 1920x1080
with `scrollWidth` equal to `innerWidth` and no overflow. That is a screenshot-compositing artifact
of the emulated viewport. **This project has been burned once by trusting a rendering artifact over
a measurement**, in the mobile audit that ADR-018 withdrew, so the DOM measurement is treated as
authoritative and the artifact is recorded rather than acted on.

## Reproduce

Serve the built UI, then run `scripts/measure-density.js` in the Browser pane at 1920x1080.
