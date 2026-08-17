// Readability gate. Paste into the console with the terminal open at any width.
//
// Computes WCAG 2.1 contrast on the COMPOSITED colour: each text run alpha-blended over its real
// backdrop, walking up the ancestor chain until an opaque background is found. Token values in
// isolation are not what a reader sees; #ffffff1f over #12131a is.
//
// PASS: smallestFontPx >= 12 and pctCharsBelowAA === 0, in every view.
(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const parse = (c) => {
    const m = c.match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const p = m[1].split(/[,\s/]+/).filter(Boolean).map(Number);
    return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
  };
  const over = (f, b) => ({
    r: f.r * f.a + b.r * (1 - f.a),
    g: f.g * f.a + b.g * (1 - f.a),
    b: f.b * f.a + b.b * (1 - f.a),
    a: 1,
  });
  const lum = (c) => {
    const f = (v) => {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
  };
  const ratio = (a, b) => {
    const l1 = lum(a), l2 = lum(b);
    return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
  };
  const bgOf = (el) => {
    let n = el, acc = null;
    while (n && n !== document.documentElement) {
      const c = parse(getComputedStyle(n).backgroundColor);
      if (c && c.a > 0) acc = acc ? over(acc, c) : c;
      if (acc && acc.a >= 1) return acc;
      n = n.parentElement;
    }
    return acc || { r: 18, g: 19, b: 26, a: 1 };
  };

  const audit = () => {
    const seen = new Map();
    const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let t = w.nextNode(); t; t = w.nextNode()) {
      const s = t.textContent.trim();
      if (!s) continue;
      const el = t.parentElement;
      if (!el) continue;
      const cs = getComputedStyle(el);
      const fg = parse(cs.color);
      if (!fg) continue;
      const bg = bgOf(el);
      const key = `${cs.fontSize}|${cs.color}|${cs.fontWeight}`;
      const rec = seen.get(key) || {
        fontPx: Number.parseFloat(cs.fontSize),
        color: cs.color,
        ratio: +ratio(over(fg, bg), bg).toFixed(2),
        chars: 0,
        sample: s.slice(0, 40),
      };
      rec.chars += s.length;
      seen.set(key, rec);
    }
    const rows = [...seen.values()].sort((a, b) => a.ratio - b.ratio);
    const total = rows.reduce((n, r) => n + r.chars, 0);
    const fail = rows.filter((r) => r.ratio < 4.5);
    const bySize = {};
    for (const r of rows) bySize[r.fontPx] = (bySize[r.fontPx] || 0) + r.chars;
    return {
      smallestFontPx: Math.min(...rows.map((r) => r.fontPx)),
      worstRatio: rows[0]?.ratio,
      medianRatio: rows[Math.floor(rows.length / 2)]?.ratio,
      pctCharsBelowAA: +((100 * fail.reduce((n, r) => n + r.chars, 0)) / total).toFixed(2),
      charsBySize: bySize,
      totalChars: total,
      worstThree: rows.slice(0, 3),
    };
  };

  const out = { viewport: `${innerWidth}x${innerHeight}`, views: {} };
  const tabs = [...document.querySelectorAll("nav button")];
  if (tabs.length === 0) {
    out.views.single = audit();
  } else {
    for (const t of tabs) {
      t.click();
      await sleep(320);
      out.views[t.innerText.replace(/\s+/g, " ").trim()] = audit();
    }
  }
  out.pass =
    Object.values(out.views).every((v) => v.smallestFontPx >= 12 && v.pctCharsBelowAA === 0);
  return out;
})();
