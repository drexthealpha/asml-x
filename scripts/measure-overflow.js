// Overflow and underflow scan. Paste into the console with the terminal open at any width.
//
// PASS: for every view, main.scrollHeight === main.clientHeight (nothing clipped),
// documentElement.scrollWidth === innerWidth (no horizontal page overflow),
// clippingBoxCount === 0 (no container hiding content it cannot scroll to),
// collapsedCellCount === 0 (no grid column resolved to near-zero while holding text).
//
// The collapsed-cell check is the one that caught a real bug a screenshot alone did not: the journal's
// ACTION column resolved to 0px because the fixed tracks already exceeded the panel width, so the most
// important field in each row was simply absent with no visual cue.
(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  const scan = () => {
    const vw = innerWidth, vh = innerHeight;
    const main = document.querySelector("main");
    let clippedText = 0, outside = 0;
    const clippingBoxes = [], collapsed = [], underflow = [];

    for (const el of document.querySelectorAll("*")) {
      const cs = getComputedStyle(el);
      if (cs.display === "none" || cs.visibility === "hidden") continue;
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) continue;

      if (el.children.length === 0 && el.textContent.trim() && el.scrollWidth > el.clientWidth + 1) {
        clippedText++;
      }
      if (r.right > vw + 1 || r.bottom > vh + 1) outside++;

      const hidesY = cs.overflowY === "hidden";
      const hidesX = cs.overflowX === "hidden";
      if (el.children.length > 0 &&
          ((hidesY && el.scrollHeight > el.clientHeight + 2) ||
           (hidesX && el.scrollWidth > el.clientWidth + 2))) {
        clippingBoxes.push({
          tag: el.tagName.toLowerCase() + "." + String(el.className).split(/\s+/).slice(0, 2).join("."),
          scrollH: el.scrollHeight, clientH: el.clientHeight,
          scrollW: el.scrollWidth, clientW: el.clientWidth,
        });
      }
    }

    for (const g of document.querySelectorAll('[class*="grid-cols"]')) {
      for (const c of g.children) {
        const r = c.getBoundingClientRect();
        // 12px is narrower than a single 12px glyph plus its bearing, so a cell this small holding
        // more than one character has lost content.
        if (r.width > 0 && r.width < 12 && c.textContent.trim().length > 1) {
          collapsed.push({ text: c.textContent.trim().slice(0, 24), w: +r.width.toFixed(1) });
        }
      }
    }

    for (const el of document.querySelectorAll(".scroll-thin")) {
      const r = el.getBoundingClientRect();
      const fill = el.scrollHeight / Math.max(1, el.clientHeight);
      if (fill < 0.7 && r.height > 80) {
        underflow.push({ clientH: el.clientHeight, contentH: el.scrollHeight, fillPct: Math.round(100 * fill) });
      }
    }

    return {
      viewport: `${vw}x${vh}`,
      mainClientH: main?.clientHeight,
      mainScrollH: main?.scrollHeight,
      mainClipsBy: (main?.scrollHeight ?? 0) - (main?.clientHeight ?? 0),
      pageScrollW: document.documentElement.scrollWidth,
      horizontalPageOverflow: document.documentElement.scrollWidth - vw,
      clippedTextCount: clippedText,
      outsideViewportCount: outside,
      clippingBoxCount: clippingBoxes.length,
      clippingBoxes: clippingBoxes.slice(0, 4),
      collapsedCellCount: collapsed.length,
      collapsedCells: collapsed.slice(0, 6),
      underflowCount: underflow.length,
      underflow: underflow.slice(0, 4),
    };
  };

  const out = { views: {} };
  const tabs = [...document.querySelectorAll("nav button")];
  if (tabs.length === 0) {
    out.views.single = scan();
  } else {
    for (const t of tabs) {
      t.click();
      await sleep(320);
      out.views[t.innerText.replace(/\s+/g, " ").trim()] = scan();
    }
  }
  out.pass = Object.values(out.views).every(
    (v) => v.mainClipsBy === 0 && v.horizontalPageOverflow <= 0 &&
           v.clippingBoxCount === 0 && v.collapsedCellCount === 0,
  );
  return out;
})();
