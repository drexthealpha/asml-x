/** Can a page at localhost fetch the X Layer testnet RPC, or does CORS block it?
 *
 * The earlier connect failure was blamed on CORS without testing. This tests it. If the fetch
 * succeeds, the real cause was latency and the fix is a longer wait, not a different chain.
 */
import { chromium } from "playwright";

const browser = await chromium.launch();
const page = await (await browser.newContext()).newPage();
await page.goto("http://127.0.0.1:4173", { waitUntil: "domcontentloaded" });

const result = await page.evaluate(async () => {
  const t0 = performance.now();
  try {
    const r = await fetch("https://testrpc.xlayer.tech", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_chainId", params: [] }),
    });
    const j = await r.json();
    return { ok: true, status: r.status, chainId: j.result, ms: Math.round(performance.now() - t0) };
  } catch (e) {
    return { ok: false, error: String(e), ms: Math.round(performance.now() - t0) };
  }
});

console.log(JSON.stringify(result, null, 2));
await browser.close();
