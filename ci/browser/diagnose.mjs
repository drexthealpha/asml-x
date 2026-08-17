/** Diagnose the three failing browser gates: what exactly is failing, and why. */
import { chromium } from "playwright";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "..", "..");
const read = (p) => readFileSync(resolve(REPO, p), "utf8");
const BASE = "http://127.0.0.1:4173";

const browser = await chromium.launch();
const page = await (await browser.newContext({ viewport: { width: 1920, height: 1080 } })).newPage();

const reqFails = [];
page.on("requestfailed", (r) => reqFails.push(`${r.method()} ${r.url()} :: ${r.failure()?.errorText}`));

await page.addInitScript(
  ({ addr, rpc }) => {
    window.ASML_ADDRESS = addr;
    window.ASML_RPC = rpc;
    globalThis.ASML_ADDRESS = addr;
    globalThis.ASML_RPC = rpc;
  },
  { addr: "0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46", rpc: "https://testrpc.xlayer.tech" },
);
await page.addInitScript(read("scripts/inject_provider.js"));
await page.goto(BASE, { waitUntil: "networkidle" });

console.log("=== 1. WHICH REQUESTS ARE REFUSED ===");
console.log([...new Set(reqFails)].slice(0, 10).join("\n") || "  none");

console.log("\n=== 2. WHAT data-testids exist on the page (pre-connect) ===");
console.log(
  JSON.stringify(
    await page.evaluate(() => [...document.querySelectorAll("[data-testid]")].map((e) => e.dataset.testid)),
  ),
);

const connect = page.getByRole("button", { name: /connect/i }).first();
if (await connect.count()) {
  await connect.click();
  await page.waitForTimeout(3000);
}

console.log("\n=== 3. data-testids AFTER connect ===");
console.log(
  JSON.stringify(
    await page.evaluate(() =>
      [...document.querySelectorAll("[data-testid]")].map((e) => [e.dataset.testid, e.textContent.trim().slice(0, 30)]),
    ),
  ),
);

console.log("\n=== 4. failure paths, per case ===");
const paths = await page.evaluate((code) => eval(code), read("scripts/failure_paths_audit.js"));
for (const c of paths.cases) {
  console.log(`  ${c.pass ? "PASS" : "FAIL"}  ${c.case}  ${JSON.stringify(c).slice(0, 220)}`);
}

await browser.close();
