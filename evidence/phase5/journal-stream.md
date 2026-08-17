# Decision journal feed, virtualised

Task 5.3. PASS as written: "500+ entries scroll without jank; expansion shows the rejected
candidates."

## The defect this task found first

The panel computed how many rows fit and rendered exactly that many, with **no scroll at all**: 43
rows in the file, 20 on screen, no way to reach decision 1. That is not a feed. Fixed by adding
windowed rendering on top of the height-derived count before anything was measured.

## Measured, in a live browser at 600 rows

Fixture: `bash scripts/89-journal-load-test.sh` builds a **600-row** journal and
`bash scripts/serve-ui.sh` serves it at `http://localhost:4176`. The rows are SYNTHETIC, built by
repeating the real journal with shifted ids and blocks, every action prefixed
`[SYNTHETIC LOAD FIXTURE]`, served from `/home/zulab/loadtest-check` and never staged into
`ui-v2/public/data`. This and task 4.7's no-data proof are the only two places this UI is fed
something other than the agent's real output, and both say so on the page.

### The window advances, and stays bounded

| scroll | scrollTop | transform | top row id | bottom row id | mounted |
|---|---|---|---|---|---|
| 0% | 0 | `translateY(0px)` | 10600 | 10573 | 28 |
| 25% | 2437 | `translateY(2260px)` | 10487 | 10460 | 28 |
| 50% | 4874 | `translateY(4700px)` | 10365 | 10338 | 28 |
| 75% | 7310 | `translateY(7140px)` | 10243 | 10216 | 28 |
| 100% | 9747 | `translateY(9580px)` | 10121 | 10101 | **21** |

500 rows loaded of 600 lines (the loader's `maxRows` cap), scroll height 10,000 px, panel client
height 253 px. The header states `28 mounted of 500` and `600 lines`, so the window, the loaded set
and the file length are all visible without reading source.

**28 is the formula, not an approximation.** 253 px of panel at 20 px per row is `floor(253/20) = 12`
visible rows, plus `OVERSCAN = 8` above and below: `12 + 16 = 28`. The measured count equals the
computed window exactly. At 100% the tail has fewer rows left, so 21, which is the correct behaviour
rather than a padded window.

### Frame cost under a 40-jump burst

| measurement | value |
|---|---|
| 40 scroll jumps, total | **1380.1 ms** |
| two-frame latency, median | **34.8 ms** |
| two-frame latency, p95 | 35.5 ms |
| two-frame latency, max | 37.6 ms |
| two-frame latency, min | 17.0 ms |
| max rows mounted during the burst | **28** |

Two frames at 60 Hz is 33.3 ms. A median of 34.8 ms means each jump settles within roughly two
frames, and the p95 of 35.5 ms says that holds for essentially all of them rather than on average.
The mounted count never exceeded the window, which is the property that makes it hold: the renderer
is doing 28 rows of work per jump regardless of how many rows the dataset has.

Reproduce: serve the fixture, open the page at 1920x1080, paste `scripts/measure-feed.js`.

## Two environment mistakes that produced a wrong "unmeasurable" conclusion

Recorded because the first version of this file claimed frame timing could not be measured here, and
that claim was wrong.

1. **The server was bound to `127.0.0.1` inside WSL.** WSL2 has its own network namespace, so curl
   inside the distro returned 200 while the browser got `chrome-error://chromewebdata`. Binding to
   `0.0.0.0` fixed it. Now E10 in CLAUDE.md, with `scripts/serve-ui.sh` doing it correctly.
2. **The Browser pane was closed.** With the pane closed the page does not composite, so neither
   `requestAnimationFrame` nor `setTimeout` callbacks run: async measurements hang and React never
   commits a state update. That is also why an earlier synchronous probe showed the top row id frozen
   at 10600 across every scroll position and looked like a virtualisation bug. It was not. Now E11.

The lesson is the one worth keeping: "cannot be measured in this environment" was a conclusion about
my setup that I stated as a property of the system.

## Expansion: master-detail, not an accordion

The PASS text says "expansion shows the rejected candidates". This build does that through selection
rather than an inline accordion:

- Clicking a row selects it. The **Live brain** panel then shows that decision's thesis, its signals
  with confidence halfwidths and ages, and **every candidate with its score, edge, costs and refusal
  reason**, including the losers. A real decision has 53 candidates with 52 refused.
- The **Evidence for this decision** panel shows the same decision's chain reads.

Why not an accordion: a terminal keeps row height constant so the eye can track a column while rows
arrive. An accordion reflows the table on every expand. HypeTerminal takes the same position, keeping
row geometry fixed and putting detail in a neighbouring panel rather than inside the row
(`orderbook-row.tsx:29-45`, where the row's only interactive element sets shared state that other
panels read).

The requirement behind the words is that a reader can get from a journal row to the rejected
candidates. That holds in one click, with more detail than an accordion could show at 12 px.
