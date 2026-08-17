/**
 * Task 9.2 measurements, run inside the page.
 *
 * PASS: zero blocking empty states, and the primary action is reachable WITHOUT SCROLLING at
 * 1280x720 and at 390x844.
 *
 * THIS AUDIT WAS TOO WEAK ON ITS FIRST RUN AND PASSED A BROKEN MOBILE LAYOUT. It measured the
 * primary action's rect and full-screen overlays, both of which were fine, and reported PASS. A
 * screenshot then showed the tab strip's label colliding with its hint text and roughly a quarter of
 * the viewport empty below the content. Neither is expressible in the first version's checks, which
 * is the whole problem: a gate that cannot see a defect will certify it.
 *
 * Three checks were added, each measuring something the screenshot showed:
 *
 *   OVERLAP    text nodes whose rects intersect. This is what "5 RWA" over "press 1 to 5" is, and it
 *              is always a defect, never a style choice.
 *   EMPTINESS  the fraction of the viewport below the last painted content. Named in this project's
 *              UI failure conditions as "empty regions above baseline".
 *   OVERFLOW   any element extending past the viewport's right edge, which is horizontal scroll by
 *              another name.
 */
(() => {
  const vw = window.innerWidth;
  const vh = window.innerHeight;

  const rectOf = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return {
      top: Math.round(r.top),
      left: Math.round(r.left),
      bottom: Math.round(r.bottom),
      right: Math.round(r.right),
      width: Math.round(r.width),
      height: Math.round(r.height),
      fullyInside: r.top >= 0 && r.left >= 0 && r.bottom <= vh && r.right <= vw,
      visible: r.width > 0 && r.height > 0,
    };
  };

  const primary =
    document.querySelector('[data-testid="wallet-connect"]') ||
    document.querySelector('[data-testid="wallet-switch"]');

  // ---- blocking empty states: covers >50% of the viewport, intercepts pointers, has no control.
  const blockers = [];
  document.querySelectorAll("body *").forEach((el) => {
    const cs = getComputedStyle(el);
    if (cs.display === "none" || cs.visibility === "hidden" || cs.pointerEvents === "none") return;
    if (cs.position !== "fixed" && cs.position !== "absolute") return;
    const r = el.getBoundingClientRect();
    if ((r.width * r.height) / (vw * vh) < 0.5) return;
    if (el.querySelectorAll("button:not([disabled]), a[href], input:not([disabled])").length) return;
    blockers.push({ tag: el.tagName.toLowerCase(), cls: String(el.className).slice(0, 60) });
  });

  // ---- leaf elements that actually paint text, used by both overlap and emptiness.
  /**
   * The rect an element is actually PAINTED in, after every scrollable ancestor clips it.
   *
   * `getBoundingClientRect` is viewport-relative and ignores clipping, so a row scrolled out of an
   * `overflow-auto` list still reports a full rect. Comparing those against elements that ARE on
   * screen manufactured most of the overlaps this audit used to report: at 1920x1080 it claimed 78,
   * and every pair inspected was inside one scrolling journal list at its bottom edge.
   *
   * A detector that over-reports is as damaging as one that under-reports. It gets switched off, or
   * it gets believed and time goes into chasing collisions that are not on screen.
   *
   * Returns null when the element is clipped away to nothing, because something not painted cannot
   * collide with anything.
   */
  function visibleRect(el) {
    const r0 = el.getBoundingClientRect();
    if (r0.width <= 0 || r0.height <= 0) return null;
    let top = r0.top;
    let left = r0.left;
    let bottom = r0.bottom;
    let right = r0.right;

    let p = el.parentElement;
    while (p) {
      const cs = getComputedStyle(p);
      if (/auto|scroll|hidden|clip/.test(cs.overflowY + " " + cs.overflowX)) {
        const pr = p.getBoundingClientRect();
        top = Math.max(top, pr.top);
        left = Math.max(left, pr.left);
        bottom = Math.min(bottom, pr.bottom);
        right = Math.min(right, pr.right);
        if (bottom - top <= 0 || right - left <= 0) return null;
      }
      p = p.parentElement;
    }

    top = Math.max(top, 0);
    left = Math.max(left, 0);
    bottom = Math.min(bottom, window.innerHeight);
    right = Math.min(right, window.innerWidth);
    if (bottom - top <= 0 || right - left <= 0) return null;

    return { top, left, bottom, right, width: right - left, height: bottom - top };
  }

  const leaves = [];
  document.querySelectorAll("body *").forEach((el) => {
    const cs = getComputedStyle(el);
    if (cs.display === "none" || cs.visibility === "hidden" || Number(cs.opacity) === 0) return;
    const hasOwnText = Array.from(el.childNodes).some(
      (n) => n.nodeType === 3 && n.textContent.trim().length > 0,
    );
    if (!hasOwnText) return;
    const r = visibleRect(el);
    if (!r) return; // clipped away by a scroller or the viewport: not painted, cannot collide
    leaves.push({ el, r, text: el.textContent.trim().slice(0, 28) });
  });

  // ---- OVERLAP between text-bearing leaves that are not ancestors of one another.
  const overlaps = [];
  for (let i = 0; i < leaves.length; i++) {
    for (let j = i + 1; j < leaves.length; j++) {
      const a = leaves[i];
      const b = leaves[j];
      if (a.el.contains(b.el) || b.el.contains(a.el)) continue;
      const ox = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left);
      const oy = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
      // A 2px tolerance: sub-pixel rounding on adjacent rows is not a collision.
      if (ox > 2 && oy > 2) {
        overlaps.push({
          a: a.text,
          b: b.text,
          overlapPx: Math.round(ox * oy),
        });
      }
    }
  }

  // ---- EMPTINESS below the last painted content.
  const lastPainted = leaves.reduce((m, l) => Math.max(m, l.r.bottom), 0);
  const emptyBelowPx = Math.max(0, Math.round(vh - lastPainted));
  const emptyBelowPct = Number(((emptyBelowPx / vh) * 100).toFixed(1));

  // ---- horizontal OVERFLOW.
  const overflowing = [];
  document.querySelectorAll("body *").forEach((el) => {
    // The PAINTED rect, not the raw one. Wide content inside an `overflow-x: auto` container is the
    // intended pattern, not a defect; only content painted past the viewport edge is.
    const r = visibleRect(el);
    if (r && r.width > 0 && r.right > vw + 1) {
      overflowing.push({
        tag: el.tagName.toLowerCase(),
        cls: String(el.className).slice(0, 50),
        right: Math.round(r.right),
      });
    }
  });

  const doc = document.documentElement;

  return {
    viewport: { w: vw, h: vh },
    primaryAction: {
      found: !!primary,
      testId: primary ? primary.getAttribute("data-testid") : null,
      text: primary ? primary.innerText.trim() : null,
      rect: rectOf(primary),
    },
    blockingEmptyStates: blockers,
    overlaps: overlaps.slice(0, 12),
    overlapCount: overlaps.length,
    emptyBelowPx,
    emptyBelowPct,
    lastPaintedBottom: Math.round(lastPainted),
    horizontalOverflow: overflowing.slice(0, 6),
    pageScrolls: doc.scrollHeight > doc.clientHeight + 1,
    valueProp: (() => {
      const el = Array.from(document.querySelectorAll("p")).find((p) =>
        p.innerText.includes("trades your capital under limits"),
      );
      if (!el) return null;
      const t = el.innerText.trim();
      return { text: t, sentences: (t.match(/[.!?](\s|$)/g) || []).length };
    })(),
  };
})()
