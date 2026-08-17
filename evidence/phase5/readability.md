# Readability: the density metric was optimising the wrong thing

Tasks 4.1 and 5.x, correction. This file exists because the terminal was genuinely hard to read and
the metric I was steering by rewarded that.

## The mechanism of the error

Ink coverage counts grid cells containing text. Smaller, dimmer text puts more rows on screen, so it
scores HIGHER. Every step that made the screen harder to read moved the number the right way:

- I invented a `--text-3xs: 10px` step and used it 25 times for explanatory prose.
- I invented `--text-muted: #6b7280`, a 45% grey, and used it 38 times.
- I set `--text-weak: #9aa1b1`, a 62% grey, for every data row.
- I set `--text-strong: #e8eaf0` instead of white.

None of those four values exists in HypeTerminal, the product this UI is supposed to be modelled on,
and its token file was on disk the whole time at `/home/zulab/hypeterminal/packages/ui/src/globals.css`
with the header "ALL values taken directly from token files".

## What their tokens actually are, and what mine were

Read from `packages/ui/src/globals.css`, dark block at lines 200 to 286:

| token | mine | theirs | measured effect |
|---|---|---|---|
| `--text-strong` | `#e8eaf0` | `#ffffff` | headings dimmed |
| `--text-weak` | `#9aa1b1` (62% grey) | `#ffffffc7` (78% white) | every data row dimmed |
| `--text-muted` | `#6b7280` (45% grey) | **does not exist** | 38 uses of an invented colour |
| `--text-3xs` | `10px` | **does not exist** | 25 uses below their 12px floor |
| `--bg-base` | `#0b0c10` | `#12131a` | mine darker, widening the gap dim text had to cross |
| `--status-long` | `#4ec9a0` | `#77c7af` | theirs lighter on the dark surface |
| `--status-short` | `#f07178` | `#ff9c9c` | same |
| `.col-label` | 10px at `--text-muted` | 12px at `--text-weak` (`orderbook-panel.tsx:104` is `text-2xs text-fg-muted`, and `globals.css:314` maps `fg-muted` to `--text-weak`) | every column header two sizes and two steps too dim |

## Measured before and after

WCAG 2.1 contrast, computed on the COMPOSITED colour: each text run alpha-blended over its real
backdrop, walking up the ancestor chain, not the token value in isolation.

| | before | after |
|---|---|---|
| smallest font size | **10px** | **12px** |
| characters below AA (4.5:1) | 0.4% at **1.44:1** worst | **0.00%** |
| worst ratio, any style | 1.44:1 | **8.28:1** |
| median ratio | not measured | **9.30:1** |
| prose size | 12px | **14px** (`--text-xs`, their Tiny step) |

8.28:1 is above WCAG **AAA** (7:1), not just AA. Reproduce by pasting `scripts/measure-contrast.js`
into the console with the terminal open.

Density did not suffer, which was the worry: largest empty rectangle came out at Decide 5.55%,
Risk 3.77%, Chain 3.29%. Larger text fills space too.

## Three real defects found only by looking at the rendered screen

The contrast numbers were the reason to look. These were found while looking.

1. **Every signal rendered as zero.** The journal field is `value_micro` for all signals, but it holds
   plain BASIS POINTS for the `_bps` ones and micro-units for the `_base` ones
   (`crates/runtime/src/main.rs:106-125` assigns `value_micro: e.value` where `e.value` is already
   bps). The UI divided everything by 1e6, so `spread_bps = -2325` displayed as `-0.00` and
   `imbalance_bps = -9176` as `-0.01`. The signals table, on a screen whose entire purpose is showing
   what the agent saw, read as all zeros.

   Now formatted per unit, inferred from the name suffix, with the unit printed. The panel shows
   `-2325 bps` and `-9176 bps`, which agree with the thesis sentence directly above them
   ("spread -2325 bps ... ask-heavy by 9176 bps"). That agreement is now checkable by eye on one
   screen, which it was not before.

   This is a WORKAROUND for a producer bug and is labelled as one in `lib/data.ts`. The durable fix is
   a `unit` field on `SignalRecord` in `crates/journal`. Recorded as a defect rather than absorbed
   silently.

2. **Truncated metric labels.** An 11-column equal-width grid clipped every label below about 1100px:
   `CHA...`, `BLO...`, `DEC...`, `TAK...`. Unreadable, and worse than showing fewer metrics. The row
   now uses `repeat(auto-fit, minmax(4.5rem, 1fr))` and wraps to a second line, with the header on a
   min-height instead of a fixed `h-8`.

3. **A fixed-height footer clipped its own text.** Raising prose to 14px made the sentence taller than
   the 24px footer, so it overlapped the panel above. Now min-height.

## The rule this replaces

Ink coverage stays as a diagnostic for finding dead regions, which is what it is good at: it found a
hidden 12-row cap on the transaction list, a duplicated panel, and two cases of data held but not
shown. It is not a quality target, and it must never be traded against type size or contrast again.

The gate that matters is the one that can be checked: **no font below 12px, and 0% of characters below
WCAG AA on the composited colour**, in every view.
