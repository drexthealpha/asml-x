/**
 * The spatial system as constants.
 *
 * Pattern applied: HypeTerminal keeps its ENTIRE layout in a 40-line constants file,
 * `apps/terminal/src/config/layout.ts:1-40`, rather than scattering sizes through
 * components. Cited in evidence/ui-study.md section 1.
 *
 * The detail worth copying most: their ANALYSIS group carries both `positions.minHeightPx: 400`
 * and `positions.disconnectedMinHeightPx: 180` (config/layout.ts:12). A panel reserves LESS
 * height when there is nothing to show. Our equivalent of "disconnected" is "the journal has no
 * rows yet", and it gets the same treatment, because an oversized panel holding one sentence is
 * one of this project's stated UI failure conditions.
 */

/** Single numeric breakpoint, not a spread of media queries (their layout.ts:1). */
export const MOBILE_BREAKPOINT_PX = 768;

/** Chrome heights as Tailwind classes held in one place (their layout.ts:32-40). */
export const CHROME = {
  HEADER_CLASS: "h-8",
  FOOTER_CLASS: "h-6",
  /**
   * NO LONGER USED as an inline height, and the reason is worth keeping.
   *
   * It was `calc(100dvh - 3.5rem)`, header plus footer. Adding the view-tab row made that arithmetic
   * wrong by the height of the tabs, and the measured `main` was 816px against the 844px this
   * claimed. Any constant that restates a sum of sibling heights goes stale the moment a sibling is
   * added, which is the failure mode HypeTerminal avoids by sizing the workspace from the viewport
   * minus chrome ONCE and letting flex distribute the rest (`main-workspace.tsx:24-30`).
   *
   * `main` now takes `flex-1 min-h-0` inside an `h-full flex flex-col` root, so the browser does the
   * subtraction and it cannot drift. Kept only as the documented floor for a standalone panel.
   */
  BODY_HEIGHT_DEPRECATED: "calc(100dvh - 3.5rem)",
} as const;

/**
 * Panel groups. Percentages plus a minimum, exactly the shape of their PANEL_LAYOUT
 * (their layout.ts:3-19).
 */
export const PANEL_LAYOUT = {
  MAIN: {
    /** Brain and journal take the left; risk and chain take the right.
     *
     * 74/26 rather than the 68/32 first tried. The right column's content is genuinely thinner
     * than the left's, and the density measurement showed the cost: at 68/32 the largest empty
     * rectangle at 1920x1080 was a 624x432 block in the bottom right, 13% of the viewport.
     * Widening the column that has rows to show is the honest fix; padding the thin column with
     * decoration is not. Measurements in evidence/phase4/density-measured.md. */
    primary: { defaultSize: "74%", minSize: "52%" },
    sidebar: { defaultSize: "26%", minSize: "20%" },
  },
  BRAIN: {
    minHeightPx: 260,
    /** No journal rows yet: reserve less, per their disconnected-height idea. */
    emptyMinHeightPx: 120,
  },
  JOURNAL: {
    minHeightPx: 220,
    emptyMinHeightPx: 96,
    /** Row height in px, asserted rather than measured: 12px text on a 16px line box plus
     * py-0.5 (2px top and bottom) is 20px. Their equivalent constant is ROW_HEIGHT = 19
     * (use-orderbook-rows.ts:3) for a 16px line box with the same padding. */
    ROW_HEIGHT_PX: 20,
    MIN_ROWS: 4,
    MAX_ROWS: 40,
    /** Rows rendered beyond the visible window, above and below.
     *
     * HypeTerminal keeps the same idea as a layout constant: `TOKEN_SELECTOR_OVERSCAN = 10` beside
     * `TOKEN_SELECTOR_ROW_HEIGHT_PX = 48` (their config/layout.ts:29-30). Overscan is what stops a
     * fast scroll showing blank bands while the next window mounts. */
    OVERSCAN: 8,
  },
  RISK: {
    minHeightPx: 240,
    emptyMinHeightPx: 96,
  },
} as const;

/**
 * Utilisation thresholds for the risk bars, in percent.
 *
 * These are display thresholds, NOT risk policy. The binding limits live in
 * crates/risk-engine and onchain in RiskGuard. A UI constant that looked like a limit would be
 * a second source of truth for something that must have exactly one.
 */
export const UTILISATION = {
  WARN_PCT: 70,
  DANGER_PCT: 90,
} as const;

/**
 * The chain this product runs on, and the one it must never be confused with.
 *
 * Here rather than inline in a component because task 5.2 is right that a chain id typed into a
 * render path is the UI asserting a fact about the chain on its own authority. The UI's job is to
 * COMPARE the loaded manifest against this expectation and colour the mismatch, which is a
 * different thing from knowing the answer.
 *
 * 195 is the deprecated X Layer testnet and it STILL ANSWERS, which is why the deprecated id is
 * named here too: a UI that only knows the right answer cannot warn about the plausible wrong one.
 */
export const CHAIN = {
  EXPECTED_ID: 1952,
  DEPRECATED_ID: 195,
} as const;

/** Where the UI reads its data from. Relative so the build works from any mount path. */
export const DATA_SOURCES = {
  journal: "data/journal.jsonl",
  learned: "data/learned-state.json",
  deployments: "data/deployments.json",
} as const;

export type DataSourceKey = keyof typeof DATA_SOURCES;

/**
 * Minimum height reserved by the connect surface, task 9.1.
 *
 * Directly modelled on HypeTerminal's `apps/terminal/src/config/layout.ts:10-14`, whose
 * `positions.disconnectedMinHeightPx: 180` reserves LESS height when the user is not connected,
 * because there is nothing to show. evidence/ui-study.md singles that out as the detail worth
 * stealing: it is a deliberate answer to "what fills this region when there is no data", which is
 * one of this project's named UI failure conditions.
 *
 * A constant here rather than a literal in the component, per task 5.2's magic-number audit.
 */
export const CONNECT_MIN_HEIGHT_PX = 140;


/**
 * Height of the persistent exit bar, task 9.5.
 *
 * A constant beside the other chrome heights, following HypeTerminal's
 * `apps/terminal/src/config/layout.ts:32-40`, where header `h-11`, footer `h-8` and banner `h-8` are
 * constants with the combined offset precomputed rather than recalculated inline.
 *
 * h-7 is 1.75rem. `EXIT_BAR_REM` exists so App.tsx adds it to the body-height arithmetic rather than
 * someone converting the Tailwind class to rem by eye.
 */
export const EXIT_BAR_CLASS = "h-7";
export const EXIT_BAR_REM = 1.75;
