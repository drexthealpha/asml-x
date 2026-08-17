/**
 * The browser gates, headless, in CI.
 *
 * WHY THIS EXISTS. These three audits were about to be declared "local only, needs the Browser
 * pane". That reasoning was wrong and worth naming: environment fact E11 says `requestAnimationFrame`
 * and `setTimeout` do not fire when THIS PROJECT'S agent harness has its preview pane closed. That is
 * a property of that pane, not of headless browsers. Headless Chromium runs both perfectly well, so
 * the gates were being skipped because of a limitation that does not apply to CI.
 *
 * The audit scripts are NOT reimplemented here. They are the same files a developer pastes into a
 * console, read off disk and evaluated in the page, so the CI result and the manual result come from
 * one implementation and cannot drift.
 *
 * The wallet is supplied by scripts/inject_provider.js, the same EIP-1193 mock ADR-016 records, via
 * addInitScript so it exists before the app boots. No browser extension is involved.
 */
import { chromium } from "playwright";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "..", "..");
const BASE = process.env.ASML_UI_URL ?? "http://127.0.0.1:4173";

const read = (p) => readFileSync(resolve(REPO, p), "utf8");

/** Evaluate an audit file in the page and return its result object. */
async function runAudit(page, file) {
  const src = read(`scripts/${file}`);
  // The audits are expressions: an async IIFE that resolves to an object. `eval` of the raw source
  // returns that promise, which page.evaluate awaits.
  return page.evaluate((code) => eval(code), src);
}

let failures = [];
function check(name, condition, detail) {
  if (condition) {
    console.log(`  PASS  ${name}`);
  } else {
    console.log(`  FAIL  ${name}  ${detail ?? ""}`);
    failures.push(name);
  }
}

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
const page = await context.newPage();

// Console errors are a gate. A page that renders while throwing is not working.
const consoleErrors = [];
page.on("console", (m) => {
  if (m.type() === "error") consoleErrors.push(m.text());
});
page.on("pageerror", (e) => consoleErrors.push(String(e)));
// The URL and status, not just "Failed to load resource". A console gate that says a request failed
// without saying which one is a gate nobody can act on, and this cost several diagnostic rounds.
const badResponses = [];
page.on("response", (r) => {
  if (r.status() >= 400) badResponses.push(`${r.status()} ${r.request().method()} ${r.url()}`);
});
page.on("requestfailed", (r) => badResponses.push(`FAILED ${r.method()} ${r.url()} :: ${r.failure()?.errorText}`));

// inject_provider.js ends with `})(ASML_ADDRESS, ASML_RPC)`, so those two globals must exist before
// it evaluates. In the manual flow an operator defines them in the console first; here they are
// defined in the same init bundle, ahead of the app's first render.
//
// READ-ONLY BY CONSTRUCTION. The address is the public deployer address and the RPC is public X
// Layer testnet. The provider only reaches for a signer when something asks it to sign, and none of
// these three audits sends a transaction, so no key is needed or present.
// POINTED AT REAL TESTNET, because the UI's contract manifest names real testnet addresses and the
// failure-path audit needs those contracts to exist. Against a local chain they do not, so an
// induced "insufficient balance" surfaced as "Failed to fetch" and the audit correctly refused it.
//
// The first version of this comment blamed CORS for a connect that never resolved. That was written
// without testing and was wrong: ci/browser/probe-cors.mjs fetches this endpoint from the page and
// gets 200 with chainId 0x7a0 in about 1.5s. The real cause was LATENCY. Connect performs several
// sequential RPC calls at roughly 1.5s each, and the harness was waiting a flat 2.5s, so it sampled
// a page that was still connecting. It now waits for the connected state itself.
const ADDRESS = process.env.ASML_ADDRESS ?? "0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46";
const RPC = process.env.ASML_PROVIDER_RPC ?? "https://testrpc.xlayer.tech";
await page.addInitScript(
  ({ addr, rpc }) => {
    window.ASML_ADDRESS = addr;
    window.ASML_RPC = rpc;
    globalThis.ASML_ADDRESS = addr;
    globalThis.ASML_RPC = rpc;
  },
  { addr: ADDRESS, rpc: RPC },
);
await page.addInitScript(read("scripts/inject_provider.js"));

// THE DASHBOARD AUDIT MUST START BEFORE THE PAGE DOES. It measures time-to-first-meaningful-data
// with a MutationObserver, so running it after load measures nothing: the data has already arrived,
// no mutation fires, and it reports `null` rather than a time. Kicked off here as an init script
// with its promise parked on `window`, and awaited further down.
// The dashboard audit is NOT started here. It measures time from ROUTE LOAD, and starting it at
// page load measures cold connect instead, which is a different number with its own claim:
// connect-to-running is 8.6s median [C-1001]. Started after connect, around a real route change.

console.log(`=== loading ${BASE} ===`);
await page.goto(BASE, { waitUntil: "networkidle" });

check("provider is injected", await page.evaluate(() => typeof window.ethereum === "object" && !!window.ethereum));
check("__asmlEmit is available", await page.evaluate(() => typeof window.__asmlEmit === "function"));

// The dashboard's tracked fields (balance, limits, fee disclosure) only exist once the wallet is
// connected, so a run that never clicks Connect measures an empty page and reports null. Connecting
// is part of the flow being audited, not a workaround for it.
const connect = page.getByRole("button", { name: /connect/i }).first();
if (await connect.count()) {
  await connect.click();
  // Waits for the CONNECTED STATE, not for a duration. A flat sleep is a race against a remote RPC,
  // and it lost: the audits ran against a page still showing "Waiting for your wallet...".
  try {
    await page.waitForSelector('[data-testid="wallet-connected"]', { timeout: 60_000 });
    const addr = await page.locator('[data-testid="wallet-address"]').first().textContent();
    const chain = await page.locator('[data-testid="wallet-chain"]').first().textContent();
    console.log(`  connected: ${addr?.trim()} on ${chain?.trim()}`);
  } catch {
    console.log("  CONNECT DID NOT COMPLETE within 60s");
  }
  // The limits and fee disclosure are read from chain after connect; wait for one of them so the
  // downstream audits see a settled page.
  await page
    .waitForSelector('[data-testid="limit-maxOrderNotional"]', { timeout: 60_000 })
    .catch(() => console.log("  limits did not render within 60s"));
} else {
  console.log("  no Connect control found; the dashboard audit will report what it sees");
}

// --- 1. Dashboard: real data fast, and loading never renders as a bare zero.
// MEASURED AROUND A REAL ROUTE CHANGE, with the wallet already connected, because that is the claim.
// C-906 says the personal dashboard shows real data within a second OF ROUTE LOAD. Measuring from a
// cold page load instead folds in the wallet connect, which against a public RPC is several
// sequential calls at about 1.5s each, and reported `null` because the audit's window closed while
// connect was still in flight. Cold connect has its own measured claim, C-1001, at 8.6s median.
console.log("\n=== dashboard audit (task 9.7) ===");
const dashSrc = read("scripts/dashboard_audit.js");
const dash = await page.evaluate(
  async (code) => {
    // Start the observer, then leave the route and come back so it observes a genuine mount.
    const pending = eval(code);
    const tabs = [...document.querySelectorAll("button")];
    const away = tabs.find((b) => /DECIDE/i.test(b.textContent || ""));
    const back = tabs.find((b) => /YOU/i.test(b.textContent || ""));
    if (away && back) {
      away.click();
      await new Promise((r) => setTimeout(r, 120));
      back.click();
    }
    return pending;
  },
  dashSrc,
);
console.log(JSON.stringify(dash, null, 2).slice(0, 700));
check("first meaningful data within 1s", dash.withinOneSecond === true, `got ${dash.firstMeaningfulMs}ms`);
check(
  "no field renders a bare zero while loading",
  Array.isArray(dash.zeroDuringLoadViolations) && dash.zeroDuringLoadViolations.length === 0,
  JSON.stringify(dash.zeroDuringLoadViolations),
);

// --- 2. Density: the stated failure condition is "empty regions above baseline".
console.log("\n=== density (task 17.5) ===");
await page.reload({ waitUntil: "networkidle" });
const density = await runAudit(page, "measure-density.js");
console.log(JSON.stringify({ ...density, panels: undefined }, null, 2).slice(0, 500));
// Thresholds from the measured baseline recorded in evidence/phase17/density.md: ink 38.13% and a
// largest void of 13.50%. These allow real slack but would catch a regression that empties the page.
check("ink coverage at least 25%", density.inkCoveragePct >= 25, `got ${density.inkCoveragePct}%`);
check(
  "largest empty rectangle under 20% of viewport",
  density.largestEmptyRect.pctOfViewport < 20,
  `got ${density.largestEmptyRect.pctOfViewport}%`,
);
check("page has numeric readouts", density.numericCells > 0, `got ${density.numericCells}`);

// --- 3. Failure paths: every induced failure recovers and names a next action.
console.log("\n=== failure paths (task 9.8) ===");
await page.reload({ waitUntil: "networkidle" });
const paths = await runAudit(page, "failure_paths_audit.js");
console.log(JSON.stringify({ passed: paths.passed, total: paths.total, deadEnds: paths.deadEnds }, null, 2));
// Print the failing cases in full. "4 of 5" without naming the one that failed is not a diagnosis,
// and CI logs are the only place anyone will look.
for (const c of paths.cases.filter((x) => !x.pass)) {
  console.log(`  FAILING CASE: ${JSON.stringify(c)}`);
}
check("no dead ends", Array.isArray(paths.deadEnds) && paths.deadEnds.length === 0, JSON.stringify(paths.deadEnds));
check("every failure case recovers", paths.pass === true, `${paths.passed}/${paths.total}`);

// --- 4. No console errors anywhere in the above.
console.log("\n=== console ===");
if (badResponses.length) {
  console.log("  non-2xx or failed requests:");
  for (const b of [...new Set(badResponses)].slice(0, 10)) console.log(`    ${b}`);
}
check("zero console errors", consoleErrors.length === 0, consoleErrors.slice(0, 3).join(" | "));

await browser.close();

console.log("");
if (failures.length) {
  console.log(`BROWSER GATES FAILED: ${failures.join(", ")}`);
  process.exit(1);
}
console.log("BROWSER GATES PASSED");
