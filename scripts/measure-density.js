// Density measurement for ui-v2. Paste into the browser console with the UI open at 1920x1080,
// or run it through a devtools protocol client. Returns ink coverage and the largest empty
// rectangle as a percentage of the viewport.
//
// WHY THIS METRIC: "empty regions above baseline" is a stated failure condition for this project's
// UI, and an impression of emptiness is not checkable. The largest all-empty axis-aligned rectangle
// is, and it corresponds to what a reader actually notices: one big void, not scattered gaps.
//
// MEASUREMENT BUG WORTH RECORDING: the first version marked any element with a background colour as
// occupied. Panel backgrounds cover the whole viewport, so it reported 100% occupied and a largest
// empty rectangle of zero, which measures nothing. This version marks only the bounding rects of
// real TEXT RUNS (via Range.getClientRects) plus the gradient bars, because density for a reader is
// about where the information is.
(() => {
  const W = innerWidth;
  const H = innerHeight;
  const CELL = 8;
  const cols = Math.floor(W / CELL);
  const rows = Math.floor(H / CELL);
  const grid = Array.from({ length: rows }, () => new Uint8Array(cols));

  const mark = (r) => {
    if (!r || r.width <= 0 || r.height <= 0) return;
    const c0 = Math.max(0, Math.floor(r.left / CELL));
    const c1 = Math.min(cols - 1, Math.ceil(r.right / CELL) - 1);
    const r0 = Math.max(0, Math.floor(r.top / CELL));
    const r1 = Math.min(rows - 1, Math.ceil(r.bottom / CELL) - 1);
    for (let y = r0; y <= r1; y++) for (let x = c0; x <= c1; x++) grid[y][x] = 1;
  };

  let textRuns = 0;
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (!n.textContent.trim()) continue;
    const range = document.createRange();
    range.selectNodeContents(n);
    for (const r of range.getClientRects()) {
      mark(r);
      textRuns++;
    }
  }
  for (const el of document.querySelectorAll(".util-bar-ok,.util-bar-warn,.util-bar-danger")) {
    mark(el.getBoundingClientRect());
  }

  // Largest all-empty rectangle, histogram method over the occupancy grid.
  const heights = new Int32Array(cols);
  let best = { area: 0, w: 0, h: 0, x: 0, y: 0 };
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) heights[x] = grid[y][x] ? 0 : heights[x] + 1;
    const stack = [];
    for (let x = 0; x <= cols; x++) {
      const h = x === cols ? 0 : heights[x];
      while (stack.length && heights[stack[stack.length - 1]] >= h) {
        const top = stack.pop();
        const left = stack.length ? stack[stack.length - 1] + 1 : 0;
        const w = x - left;
        const hh = heights[top];
        if (w * hh > best.area) best = { area: w * hh, w, h: hh, x: left, y: y - hh + 1 };
      }
      stack.push(x);
    }
  }

  let occupied = 0;
  for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) occupied += grid[y][x];

  return {
    viewport: `${W}x${H}`,
    cellPx: CELL,
    textRuns,
    inkCoveragePct: +((100 * occupied) / (rows * cols)).toFixed(2),
    largestEmptyRect: {
      wPx: best.w * CELL,
      hPx: best.h * CELL,
      atPx: `${best.x * CELL},${best.y * CELL}`,
      pctOfViewport: +((100 * best.w * CELL * best.h * CELL) / (W * H)).toFixed(2),
    },
    numericCells: document.querySelectorAll(".num").length,
    panels: [...document.querySelectorAll("section")].map((s) => {
      const r = s.getBoundingClientRect();
      return {
        title: s.querySelector("h2")?.textContent,
        wPx: Math.round(r.width),
        hPx: Math.round(r.height),
      };
    }),
  };
})();
