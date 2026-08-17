// Task 5.3 feed measurement. Paste into the console with the load fixture open.
//
// The claim being tested is "500+ entries scroll without jank". Jank is not directly observable from
// script, so what is measured instead are the two things that CAUSE it and that can be counted
// exactly: how many rows are mounted at once, and how long a scroll-driven re-render takes.
//
// A virtualised list that mounts all 600 rows is virtualised in name only, and the mounted count is
// the honest way to tell.
(async () => {
  const panel = [...document.querySelectorAll("section")].find((s) =>
    /DECISION JOURNAL/i.test(s.innerText),
  );
  if (!panel) return { error: "journal panel not found" };

  const scroller = panel.querySelector(".scroll-thin");
  if (!scroller) return { error: "scroll container not found" };

  const countRows = () => panel.querySelectorAll("button.grid").length;
  const meta = () => panel.querySelector("header")?.innerText.replace(/\s+/g, " ");

  const frame = () => new Promise((r) => requestAnimationFrame(() => r()));

  const samples = [];
  const mounted = [];
  const positions = [0, 0.25, 0.5, 0.75, 1];

  for (const p of positions) {
    const top = Math.round((scroller.scrollHeight - scroller.clientHeight) * p);
    const t0 = performance.now();
    scroller.scrollTop = top;
    await frame();
    await frame();
    const t1 = performance.now();
    samples.push(+(t1 - t0).toFixed(2));
    mounted.push(countRows());
  }

  // Rapid burst: 40 scroll jumps back to back, the case that exposes a missing overscan.
  const burstStart = performance.now();
  for (let i = 0; i < 40; i++) {
    scroller.scrollTop = (i * scroller.scrollHeight) / 40;
    await frame();
  }
  const burstMs = performance.now() - burstStart;

  return {
    scrollHeightPx: scroller.scrollHeight,
    clientHeightPx: scroller.clientHeight,
    rowHeightImpliedPx: Math.round(scroller.scrollHeight / (mounted.length ? 600 : 1)),
    mountedRowsAtPositions: mounted,
    maxMountedRows: Math.max(...mounted),
    twoFrameLatencyMs: samples,
    burstOf40JumpsMs: +burstMs.toFixed(1),
    avgFrameMsDuringBurst: +(burstMs / 40).toFixed(2),
    panelMeta: meta(),
    totalRowsInDataset: 600,
  };
})();
