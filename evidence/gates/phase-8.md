# Phase 8 gate: the UI

Captured 9 Aug 2026. `ui/index.html`, served by `scripts/35-serve-ui.sh`.

## What it shows

One page, eight panels, all read from real artifacts at load time:

| panel | source |
|---|---|
| Chain and deployment | `deployments.json`, with explorer links per contract |
| Risk and limit utilisation | `evidence/journal.jsonl`, refusal counts grouped by reason |
| RWA instrument | journal, plus the SELF-DEPLOYED STAND-IN provenance badge |
| Learning | `evidence/learned-state.json` |
| Current thesis and signals | latest journal entry, with confidence and input age per signal |
| Scored candidate set | latest entry's full candidate list, rejects included, four score terms each |
| Decision journal | last 40 entries, newest first, tx hashes as explorer links |
| Measured numbers | derived from the journal |

Single HTML file, no build step, no framework, no external requests. It works from
`file://` and over HTTP.

## Live render, DEMONSTRATED

Loaded against the real repo it displayed: 87 journal entries, 79 cycles containing a
refusal, `OrderNotionalTooLarge` refused 40 times, learning state with 2 settled outcomes
and 1 unscored flat sample, the live thesis at block 37833004, and a candidate table where
the chosen action and every rejected alternative carry their own score breakdown.

## The anti-fake-win check: the UI cannot fake data

The named fake win was "a beautiful dashboard fed by a fixture file". The counter-task was
to run it with no data and confirm it says so rather than showing plausible numbers.

`ui/nodata-check/index.html` is the same page in a directory whose relative data paths
resolve to nothing. Loaded, it renders:

- Chain and deployment: "deployments.json not readable"
- Risk: "no journal entries, runtime has not run"
- Learning: "learned-state.json not readable, learning has not run"
- Thesis, candidates, journal: "no journal entries" / "journal.jsonl is empty or missing"
- Measured numbers: 0 and n/a, never invented values
- Header badge: "DISCONNECTED, no data files readable"

Panels that lose their source also get a red border, so a judge sees the failure without
reading text.

## Two real defects the UI exposed

Both were invisible in passing tests and only appeared once the data was on screen.

1. **A crossed book was paying the agent to trade.** The live thesis showed a spread of
   **-1333 bps**: the simulator had posted a bid above the resting ask, so the book was
   crossed. My scorer subtracted the spread as a crossing cost, and a negative spread
   became a CREDIT that inflated expected edge on every candidate. Fixed by flooring the
   crossing cost at zero, disclosing the crossing in the thesis text, and ZEROING thesis
   confidence when crossed rather than diluting it (averaging one zero into the other
   terms still left 833 bps of confidence on a meaningless spread). Pinned by two unit
   tests and three integration tests in `crates/decision-engine/tests/crossed_book.rs`,
   including one asserting a tighter spread must score better than a wide one, and one
   asserting the risk gate still governs a crossed book.
2. **The footer claimed nothing was hardcoded while two values were.** Block time and gas
   price were transcribed from `docs/verified/chain-1952-reality.md`, not read live. They
   now carry a "from docs/verified" badge and the footer states the exception. A page that
   overclaims its own provenance undermines every other number on it.

## Not done

- Not deployed publicly. It is a static file, so Vercel or Cloudflare Pages will host it
  as-is, but that is a Phase 9 task and it has not been done.
- No live websocket. The page reads files at load and does not auto-refresh; reload to
  update. Stated rather than implied by the word "dashboard".
- The coordination playground from the plan's 8.1.6 is not built. The API exists and the
  external Python agent exercises it, but there is no in-browser control for it.
- No "Run demo scenario" button (plan 8.1.7). Running the demo means running the scripts.

## Verification position after this phase

19 test suites green across the workspace, zero failures. Mutation gates: 14/14 risk
engine, 15/15 contracts, 18/18 RWA, 12/12 learning. Formal: 7 + 7 Halmos theorems, each
with an injected violation caught.
