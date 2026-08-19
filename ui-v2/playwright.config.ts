import { defineConfig, devices } from "@playwright/test";

/**
 * E2E configuration.
 *
 * THE SERVER IS NOT STARTED HERE. `webServer` would rebuild and serve the app, but this product's
 * surfaces are fed by `scripts/feed_server.py`, which signs OKX requests with credentials that live
 * outside the repo. Starting only the static server would produce a suite that passes against
 * empty feeds, which is the "test that cannot fail" this project deletes on sight.
 *
 * So the suite runs against an already-running pair (`bash scripts/221-feed-server.sh`) and fails
 * loudly if it is not there. A red suite that says "nothing was running" is more useful than a
 * green one that measured nothing.
 */
export default defineConfig({
  testDir: "./e2e",
  // Serial. The surfaces share one polled feed server, and parallel workers would multiply the
  // API load against a real rate-limited key for no benefit at this suite size.
  workers: 1,
  fullyParallel: false,
  timeout: 45_000,
  expect: { timeout: 10_000 },
  reporter: [["list"], ["json", { outputFile: "../evidence/phase20/e2e-results.json" }]],
  use: {
    baseURL: process.env.ASML_UI ?? "http://127.0.0.1:4173",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"] } },
  ],
});
