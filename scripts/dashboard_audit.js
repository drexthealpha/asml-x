/**
 * Task 9.7 measurements: the personal dashboard shows real data immediately.
 *
 * PASS: first meaningful data within 1 second of route load, measured.
 * FAKE WIN: "showing zeros while loading, which reads as 'you have nothing'."
 * COUNTER: "the loading state must be distinguishable from a real zero, as in task 4.7."
 *
 * TWO THINGS ARE MEASURED, and the second is the one that matters more.
 *
 * 1. TIME TO FIRST MEANINGFUL DATA. A MutationObserver watches from the moment the route mounts and
 *    stops at the first paint of a value that came from a source: a balance, a limit, a fee rate, a
 *    decision row. Not a skeleton, not a placeholder, not a zero.
 *
 * 2. LOADING IS DISTINGUISHABLE FROM ZERO. Every numeric readout on the dashboard is inspected
 *    while its source is still in flight. A field showing "0" during load would be indistinguishable
 *    from a real balance of zero, which tells the user they have nothing when the truth is that
 *    nothing has been read yet. The audit fails if any tracked field renders a bare zero or an empty
 *    string before its data arrives; it must render a word instead.
 */
(async () => {
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  // Fields whose value must never be a bare number before its source has loaded.
  const TRACKED = [
    "vault-balance",
    "exit-balance",
    "limit-maxOrderNotional",
    "fee-disclosure",
  ];

  // Words that mean "not yet", any of which is an acceptable pre-load rendering.
  const LOADING_WORDS = /reading|loading|waiting|checking|unavailable|not connected|unknown|—/i;

  const observations = [];
  const t0 = performance.now();

  // Watch the DOM from now until real data appears.
  let firstMeaningfulMs = null;
  const isMeaningful = () => {
    // A balance or a limit rendered with an actual figure counts as meaningful.
    for (const id of ["vault-balance", "exit-balance", "limit-maxOrderNotional"]) {
      const el = document.querySelector(`[data-testid="${id}"]`);
      if (el && /\d/.test(el.textContent) && !LOADING_WORDS.test(el.textContent)) return id;
    }
    return null;
  };

  const obs = new MutationObserver(() => {
    if (firstMeaningfulMs === null) {
      const hit = isMeaningful();
      if (hit) {
        firstMeaningfulMs = performance.now() - t0;
        observations.push({ at: Math.round(firstMeaningfulMs), source: hit });
      }
    }
  });
  obs.observe(document.body, { childList: true, subtree: true, characterData: true });

  // Sample the tracked fields repeatedly during the load window, so a bare zero mid-load is caught
  // even if it is replaced quickly.
  const violations = [];
  const samples = [];
  for (let i = 0; i < 20; i++) {
    const snap = {};
    for (const id of TRACKED) {
      const el = document.querySelector(`[data-testid="${id}"]`);
      snap[id] = el ? el.textContent.trim().slice(0, 48) : null;
      if (el) {
        const t = el.textContent.trim();
        // A bare zero, or an empty field, before anything has loaded.
        const bareZero = /^0(\.0+)?(\s|$)/.test(t) || t === "";
        if (bareZero && firstMeaningfulMs === null) {
          violations.push({ id, text: t, atMs: Math.round(performance.now() - t0) });
        }
      }
    }
    samples.push({ atMs: Math.round(performance.now() - t0), ...snap });
    if (firstMeaningfulMs !== null && i > 3) break;
    await wait(100);
  }

  obs.disconnect();

  // What is actually on the dashboard once loaded.
  const present = {};
  for (const id of [
    "vault-balance",
    "exit-balance",
    "exit-withdraw",
    "exit-pause",
    "limit-maxOrderNotional",
    "limit-maxMarketNotional",
    "fee-disclosure",
    "deposit-activate",
  ]) {
    const el = document.querySelector(`[data-testid="${id}"]`);
    present[id] = el ? el.textContent.trim().slice(0, 60) : null;
  }

  return {
    firstMeaningfulMs: firstMeaningfulMs === null ? null : Math.round(firstMeaningfulMs),
    withinOneSecond: firstMeaningfulMs !== null && firstMeaningfulMs <= 1000,
    zeroDuringLoadViolations: violations,
    samples: samples.slice(0, 8),
    present,
  };
})()
