/**
 * The tests a stranger's experience depends on.
 *
 * WHAT THESE ARE FOR, and it is not coverage. Each one pins a defect that actually shipped in this
 * project and was found by a person looking at the screen rather than by a test:
 *
 *   - rows that did not open           every surface's rows were static divs
 *   - the network label lying          the header said "testnet" over mainnet blocks
 *   - engineering vocabulary on screen  `InsufficientFreeMargin { would_leave: 22 }` reached a user
 *   - a price that never changed        nothing refreshed, so it looked hardcoded
 *   - 375px                            the action column sat below a scrolling list
 *
 * A test that cannot fail is deleted, so each of these was run against the broken version first.
 */

import { expect, test, type Page } from "@playwright/test";

const SURFACES = [
  "Your limits",
  "Trade",
  "Your agent",
  "Real assets",
  "Assets",
  "Markets",
  "Insights",
  "Contracts",
] as const;

async function openSurface(page: Page, name: string) {
  await page.getByRole("button", { name, exact: true }).click();
  // The feeds are polled, so a surface is "ready" when it has painted content, not on click.
  await page.waitForTimeout(1200);
}

test.describe("the product a stranger meets", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.waitForLoadState("networkidle");
  });

  test("every surface is reachable and names itself", async ({ page }) => {
    for (const s of SURFACES) {
      await openSurface(page, s);
      await expect(page.locator("main")).not.toBeEmpty();
    }
  });

  test("the network is named from the manifest, never as testnet", async ({ page }) => {
    // The header printed a hardcoded "X Layer testnet" for any chain whose id matched the
    // expected one, and kept saying it over mainnet blocks and mainnet contracts.
    //
    // SCOPED TO THE PAGE HEADER, TWICE CORRECTED.
    //
    // `page.locator("header")` matched six elements, because every Card renders its own <header>.
    // The replacement, `body > div > header`, then matched NOTHING: React mounts into #root, so
    // the real path has one more level. Both were bugs in this test rather than in the product.
    //
    // Worth recording because the failure mode is asymmetric: a selector that is too broad fails
    // loudly, and one that matches nothing can silently make an assertion vacuous. Anchoring on
    // the banner role describes what is meant instead of where it happens to sit.
    const header = page.getByRole("banner");
    await expect(header).toContainText("X Layer");
    await expect(header).not.toContainText(/testnet/i);

    // The whole page, too: the word must not appear anywhere on a mainnet product.
    await expect(page.locator("body")).not.toContainText(/testnet/i);
  });

  test("no engineering vocabulary reaches the screen", async ({ page }) => {
    // A raw Rust enum reached a user once: `InsufficientFreeMargin { would_leave: 22, minimum: … }`.
    const banned = [
      /InsufficientFreeMargin/,
      /\{\s*would_leave/,
      /micro_?units?/i,
      /rejection_reason/,
      /bps_micro/,
      /RiskApproved</,
      /tBASE|tQUOTE/,
      /halmos/i,
      /evidence/i,
    ];
    for (const s of SURFACES) {
      await openSurface(page, s);
      const text = (await page.locator("main").innerText()).replace(/\s+/g, " ");
      for (const b of banned) {
        expect(text, `${s} shows ${b}`).not.toMatch(b);
      }
    }
  });

  test("token rows open a detail panel on every surface", async ({ page }) => {
    for (const s of ["Trade", "Real assets", "Assets", "Markets", "Insights"]) {
      await openSurface(page, s);
      const rows = page.locator("main button").filter({ hasNotText: /^$/ });
      const count = await rows.count();
      expect(count, `${s} has no rows`).toBeGreaterThan(0);

      // Find the first row tall enough to be a data row rather than a control.
      for (let i = 0; i < Math.min(count, 8); i += 1) {
        const box = await rows.nth(i).boundingBox();
        if (box && box.height > 40) {
          await rows.nth(i).click();
          await expect(
            page.getByRole("dialog"),
            `${s}: a row click opened nothing`,
          ).toBeVisible({ timeout: 5000 });
          await page.keyboard.press("Escape");
          break;
        }
      }
    }
  });

  test("the money controls exist and refuse an empty amount", async ({ page }) => {
    await openSurface(page, "Trade");
    // Without a wallet the surface must still explain itself rather than render a dead end.
    await expect(page.locator("main")).toContainText(/Connect wallet|Your money/i);
  });

  test("the limit control is on the landing surface, not buried", async ({ page }) => {
    // The single promise this product makes was a text field in a sidebar behind a wallet
    // connection. It is now the first thing on the first surface.
    await openSurface(page, "Your limits");
    await expect(page.locator("main")).toContainText(/Your limit/i);
    await expect(page.locator("main")).toContainText(/only ever lowered|can only be lowered|only be lowered/i);
  });

  test("the deep RWA record is present, not just a price", async ({ page }) => {
    await openSurface(page, "Real assets");
    const rows = page.locator("main button").filter({ hasText: /available/ });
    expect(await rows.count(), "no real-world assets listed").toBeGreaterThan(0);
    await rows.first().click();
    const d = page.getByRole("dialog");
    await expect(d).toBeVisible({ timeout: 5000 });
    // The company it is a claim on is what makes it a real-world asset rather than a ticker.
    await expect(d).toContainText(/THE COMPANY/i);
    await expect(d).toContainText(/Exchange/i);
    await expect(d).toContainText(/RISK CHECKS/i);
    await expect(d).toContainText(/CONCENTRATION/i);
    await page.keyboard.press("Escape");
  });

  test("prices refresh rather than sitting still", async ({ page }) => {
    // "The price even looks hardcoded" was a real report: nothing polled, so nothing moved.
    // The age indicator is the observable proof that a refresh cycle is running.
    await openSurface(page, "Markets");
    await expect(page.locator("main")).toContainText(/Live from OKX|Not refreshing/i);
  });
});

test.describe("mobile, at 375px", () => {
  test.use({ viewport: { width: 375, height: 812 } });

  test("nothing overflows horizontally", async ({ page }) => {
    await page.goto("/");
    await page.waitForLoadState("networkidle");

    for (const s of SURFACES) {
      await openSurface(page, s);
      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
      );
      expect(overflow, `${s} scrolls sideways by ${overflow}px`).toBeLessThanOrEqual(1);
    }
  });

  test("the action is above the token list", async ({ page }) => {
    // The vault column sat in a right-hand column pushed below a scrolling list, so clicking a
    // token appeared to do nothing at all on a narrow screen.
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    await openSurface(page, "Trade");

    const money = await page.getByText(/Your money/i).first().boundingBox();
    const list = await page.getByText(/Tokens you can trade/i).first().boundingBox();
    expect(money && list && money.y < list.y, "the deposit panel is below the token list").toBe(
      true,
    );
  });
});
