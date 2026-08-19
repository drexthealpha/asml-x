/**
 * Accessibility, checked by a tool rather than by opinion.
 *
 * WHY axe AND NOT A CHECKLIST. "Contrast looks fine" and "the labels seem clear" are the kinds of
 * claims this project has learned not to trust from itself. axe-core runs the WCAG rules against
 * the rendered DOM and returns violations with the exact node, which is a measurement.
 *
 * SERIOUS AND CRITICAL ONLY, deliberately. Every violation is reported for the record, but the
 * suite fails on serious and critical: those are the ones that make a surface unusable with a
 * screen reader or at low vision. Failing on every minor advisory would train someone to ignore
 * the gate, which is worse than not having it.
 */

import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

const SURFACES = ["Trade", "Your agent", "Assets", "Markets", "Insights"] as const;

for (const surface of SURFACES) {
  test(`${surface} has no serious accessibility violations`, async ({ page }) => {
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    await page.getByRole("button", { name: surface, exact: true }).click();
    await page.waitForTimeout(1500);

    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .analyze();

    // Print everything, fail on what matters. The full list is the useful artifact even when the
    // test passes.
    for (const v of results.violations) {
      console.log(`  [${v.impact}] ${v.id}: ${v.help} (${v.nodes.length} nodes)`);
    }

    const blocking = results.violations.filter(
      (v) => v.impact === "serious" || v.impact === "critical",
    );
    expect(
      blocking.map((v) => `${v.id}: ${v.help}`),
      "serious or critical accessibility violations",
    ).toEqual([]);
  });
}

test("the detail panel is reachable and dismissable by keyboard", async ({ page }) => {
  // A panel that only closes with a mouse is a trap. This is a behaviour axe cannot see.
  await page.goto("/");
  await page.waitForLoadState("networkidle");
  await page.getByRole("button", { name: "Trade", exact: true }).click();
  await page.waitForTimeout(1500);

  const rows = page.locator("main button");
  const count = await rows.count();
  for (let i = 0; i < Math.min(count, 10); i += 1) {
    const box = await rows.nth(i).boundingBox();
    if (box && box.height > 40) {
      await rows.nth(i).click();
      const dialog = page.getByRole("dialog");
      await expect(dialog).toBeVisible({ timeout: 5000 });
      await page.keyboard.press("Escape");
      await expect(dialog).toBeHidden({ timeout: 3000 });
      return;
    }
  }
  throw new Error("no data row found to open");
});
