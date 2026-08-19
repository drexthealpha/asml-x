# Design system, and the layout defect it exposed

Evidence for the UI/UX rebuild. Every number below was read off the running page at
`http://127.0.0.1:4173` serving `ui-v2/dist`, not estimated.

## The two skills, installed rather than paraphrased

| Skill | Source | Local path |
|---|---|---|
| `frontend-design` | `github.com/anthropics/skills`, sparse checkout of `skills/frontend-design` | `~/.claude/skills/anthropic-skills/skills/frontend-design/SKILL.md` |
| `ui-ux-pro-max` v2.13.0 | `github.com/nextlevelbuilder/ui-ux-pro-max-skill` | `~/.claude/skills/ui-ux-pro-max-skill` |

Both were cloned through WSL. Git Bash on this machine cannot resolve `github.com`
(CLAUDE.md E9); the WSL distro can, which is the documented workaround and not a new finding.

The UI/UX Pro Max generator was run for real, not read:

```
python3 scripts/search.py "fintech defi vault dashboard institutional dark" \
  --design-system --variance 6 --motion 3 --density 8 -p "ASML-X" -f markdown
```

It returned pattern "Trust & Authority + Conversion", style "Minimalism & Swiss Style",
type pairing Space Grotesk + Inter + JetBrains Mono, and a gold/purple palette.

**Two of its four recommendations were overridden, and the reason is recorded here rather than
left implicit.** The `frontend-design` skill states that where a brief pins down a visual
direction, the brief's own words win. This brief pins ADR-013 exactly: Zinc base, Emerald,
Amber, Blue, Red.

| Generator said | Shipped | Why |
|---|---|---|
| Primary `#F59E0B` gold, accent `#8B5CF6` purple | ADR-013 four-hue status palette on Zinc | The brief specifies the palette hex by hex, and its own anti-pattern list bans "AI purple/pink gradients" two lines below where it proposed a purple accent |
| Body face Inter | IBM Plex Sans | The brief bans "generic Inter defaults" in as many words |
| Display Space Grotesk | kept | Mechanical terminals suit an instrument |
| Mono JetBrains | IBM Plex Mono | Same superfamily as the body face, so a figure and its label share a skeleton |

## Palette, validated rather than eyeballed

```
node scripts/validate_palette.js "#10B981,#F59E0B,#3B82F6,#EF4444" --mode dark
```

- contrast vs surface: PASS, all four at or above 3:1
- CVD adjacent-pair separation: PASS
- normal-vision separation: PASS
- lightness band: FAIL, and **scoped to categorical use only**, which is the use these never
  get. The validator says so on its own last line. These are status colours: reserved, never a
  chart series, and every appearance carries a Lucide icon and a word.

That last rule is enforced structurally, not by convention. `components/status.tsx` exposes a
closed `StatusKind` union; there is no call that produces a bare coloured dot, because the icon
and the label are looked up from the same table as the colour.

## Typefaces actually load

Read from `document.fonts` on the live page:

```
Space Grotesk Variable  300 700   loaded
IBM Plex Sans Variable  100 700   loaded
IBM Plex Mono           400       loaded
document.fonts.check('600 46px "Space Grotesk Variable"')  true
```

Self-hosted through `@fontsource`, bundled by Vite. No `fonts.googleapis.com` request, so first
paint does not depend on a third party and the app still renders with no network.

## The layout defect, measured and fixed

The screenshots showed text painted over text on the You surface. A clipping-aware overlap
audit run against the live DOM at 375x812 found it:

```
before:  overlaps 3   worst 11,746 px^2   "No browser wallet detected" over the footer bar
after:   overlaps 1   worst    904 px^2   a single element straddling main's scroll edge,
                                          cleanly clipped by overflow rather than painted over
horizontal scroll: 0 at both 375px and 632px
```

**Cause.** `main` was sized `max(calc(100dvh - 5rem), 416px)`. The `5rem` was a hand-counted
guess at the header plus the tab row plus the exit bar. That guess is correct at exactly one
width. At 375px both bars wrap to a second line, real chrome exceeds 5rem, and `main` claimed
more height than the viewport had left, so the footer landed on top of the content.

**Fix.** `main` is now `flex-1 min-h-0` inside the `h-full flex flex-col` shell and asks the
browser for the space that is actually left. `CHROME_REM`, `chromeRem()` and the `EXIT_BAR_REM`
import are deleted, so there is no constant left to fall out of sync.

Shell geometry after the fix, summing exactly to the viewport at both widths tested:

```
375 x 812   HEADER 0-75    NAV 75-102   MAIN 102-759   FOOTER 759-812
632 x 606   HEADER 0-39    NAV 39-66    MAIN  66-569   FOOTER 569-606
```

632px is the width the previous layout comment records as clipping with `clientHeight 466`
against `scrollHeight 6945`. It no longer clips.

## Accessibility baseline added with the tokens

- `:focus-visible` ring at 2px in the telemetry blue on every focusable element. The browser
  default 1px outline is invisible against Zinc 950, which is how a console becomes
  keyboard-hostile without anyone noticing.
- `prefers-reduced-motion` honoured globally. The emblem's ring and the live pulse are the only
  animations in the product and both stop.
- `.sr-only` for accessible names on icon-only controls.
- Light mode accents re-picked at darker steps rather than flipped, because the dark values do
  not clear 4.5:1 against Zinc 50.
