/**
 * Task 9.5 measurements: Pause and Withdraw visible at every route and both viewport sizes.
 *
 * PASS: "both controls are in the DOM and visible at every route and both viewport sizes, verified
 * by measurement rather than by screenshot."
 * FAKE WIN: "controls present but below the fold."
 * COUNTER: "the audit asserts each control's bounding rect is inside the viewport."
 *
 * SO "VISIBLE" IS DEFINED, not assumed. Present in the DOM is necessary and nowhere near
 * sufficient, and a screenshot cannot distinguish a control at the fold from one just past it. A
 * control counts as visible only if ALL of these hold:
 *
 *   1. its bounding rect is entirely inside the viewport
 *   2. it has non-zero area
 *   3. computed display, visibility and opacity do not hide it
 *   4. `elementFromPoint` at its centre lands on the control or a descendant, so nothing is
 *      painted over it. A button underneath an overlay passes every rect check and is unclickable.
 *
 * Check 4 is the one that catches the failure a rect test cannot see, which is why it is here rather
 * than assumed away.
 */
(async () => {
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const IDS = ["exit-withdraw", "exit-pause"];

  function assess(id) {
    const el = document.querySelector(`[data-testid="${id}"]`);
    if (!el) return { id, present: false };

    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    const vw = window.innerWidth;
    const vh = window.innerHeight;

    const insideViewport =
      r.top >= 0 && r.left >= 0 && r.bottom <= vh && r.right <= vw && r.width > 0 && r.height > 0;
    const notHidden =
      cs.display !== "none" && cs.visibility !== "hidden" && Number(cs.opacity) > 0;

    // Is anything painted on top of it?
    const cx = Math.round(r.left + r.width / 2);
    const cy = Math.round(r.top + r.height / 2);
    const hit = document.elementFromPoint(cx, cy);
    const reachable = !!hit && (hit === el || el.contains(hit) || hit.contains(el));

    return {
      id,
      present: true,
      text: el.textContent.trim().slice(0, 40),
      disabled: !!el.disabled,
      rect: {
        top: Math.round(r.top),
        left: Math.round(r.left),
        bottom: Math.round(r.bottom),
        right: Math.round(r.right),
        w: Math.round(r.width),
        h: Math.round(r.height),
      },
      insideViewport,
      notHidden,
      reachable,
      hitElement: hit ? hit.tagName.toLowerCase() : null,
      visible: insideViewport && notHidden && reachable,
    };
  }


  /**
   * Whole-page integrity at the current route: overlapping text and horizontal overflow.
   *
   * Same measurements as scripts/landing_audit.js, because "is this control visible" and "is this
   * page intact" are different questions and the first one alone certified a broken layout.
   */
  function pageIntegrity() {
    const vw = window.innerWidth;
    const vh = window.innerHeight;

  
  /**
   * The rect an element is actually PAINTED in, after every scrollable ancestor clips it.
   *
   * `getBoundingClientRect` is viewport-relative and ignores clipping, so a row scrolled out of an
   * `overflow-auto` list still reports a full rect. Comparing those against elements that ARE on
   * screen manufactured most of the overlaps this audit used to report. Returns null when the
   * element is clipped away to nothing.
   */
  function visibleRect(el) {
    let r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return null;
    let top = r.top, left = r.left, bottom = r.bottom, right = r.right;

    let p = el.parentElement;
    while (p) {
      const cs = getComputedStyle(p);
      const clips =
        /auto|scroll|hidden|clip/.test(cs.overflowY) || /auto|scroll|hidden|clip/.test(cs.overflowX);
      if (clips) {
        const pr = p.getBoundingClientRect();
        top = Math.max(top, pr.top);
        left = Math.max(left, pr.left);
        bottom = Math.min(bottom, pr.bottom);
        right = Math.min(right, pr.right);
        if (bottom - top <= 0 || right - left <= 0) return null;
      }
      p = p.parentElement;
    }
    // Finally clip to the viewport itself.
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
      const ownText = Array.from(el.childNodes).some(
        (n) => n.nodeType === 3 && n.textContent.trim().length > 0,
      );
      if (!ownText) return;
      const r = visibleRect(el);
      if (!r) return; // clipped away by a scroller or the viewport: not painted, cannot collide
      leaves.push({ el, r, text: el.textContent.trim().slice(0, 28) });
    });

    const overlaps = [];
    for (let i = 0; i < leaves.length; i++) {
      for (let j = i + 1; j < leaves.length; j++) {
        const a = leaves[i];
        const b = leaves[j];
        if (a.el.contains(b.el) || b.el.contains(a.el)) continue;
        const ox = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left);
        const oy = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
        if (ox > 2 && oy > 2) overlaps.push({ a: a.text, b: b.text });
      }
    }

    const overflowing = [];
    document.querySelectorAll("body *").forEach((el) => {
      // The PAINTED rect, not the raw one. Wide content inside an `overflow-x: auto` container is
      // the intended pattern, not a defect; only content painted past the viewport edge is.
      const r = visibleRect(el);
      if (r && r.width > 0 && r.right > vw + 1) {
        overflowing.push({ tag: el.tagName.toLowerCase(), right: Math.round(r.right) });
      }
    });

    return {
      overlapCount: overlaps.length,
      overlaps: overlaps.slice(0, 6),
      horizontalOverflowCount: overflowing.length,
      horizontalOverflow: overflowing.slice(0, 4),
    };
  }

  // Every route, driven through the real tab buttons rather than by setting state.
  const tabs = Array.from(document.querySelectorAll("nav button, [role=tablist] button")).filter(
    (b) => /^\d/.test(b.textContent.trim()),
  );
  const routes = [];

  for (const tab of tabs) {
    tab.click();
    await wait(700);
    routes.push({
      route: tab.textContent.trim(),
      controls: IDS.map(assess),
      barPresent: !!document.querySelector('[data-testid="exit-bar"]'),
      ...pageIntegrity(),
    });
  }

  const allVisible = routes.every((r) => r.controls.every((c) => c.present && c.visible));
  const totalOverlaps = routes.reduce((n, r) => n + r.overlapCount, 0);
  const totalOverflow = routes.reduce((n, r) => n + r.horizontalOverflowCount, 0);

  return {
    viewport: { w: window.innerWidth, h: window.innerHeight },
    routesChecked: routes.length,
    routes,
    allVisibleEverywhere: allVisible,
    totalOverlaps,
    totalOverflow,
    // A control can be perfectly placed on a page that is falling apart around it. The rect-only
    // version of this audit passed a layout whose exit bar was painting over the tab strip.
    pass: allVisible && totalOverlaps === 0 && totalOverflow === 0,
  };
})()
