/**
 * View tabs, task 5.x layout correction.
 *
 * WHY THIS EXISTS: everything was being forced onto one 1920x1080 screen. Eight panels competed for
 * the same pixels, each one shrank to a strip, and the layout got shuffled repeatedly to chase a
 * density metric. That is the wrong solution to the wrong problem. HypeTerminal does not put its
 * whole product on one surface: it TABS panels whose content is alternative views of the same
 * question (`orderbook-panel.tsx:87-101`, Order Book and Trades in one panel with
 * `orderbook-panel.tsx:102` giving the tab content `flex-1 min-h-0 mt-0 pt-0 flex flex-col`), and it
 * routes between whole workspaces. I cited that pattern in the study and then ignored it.
 *
 * Tabs also make the density target reachable HONESTLY. A void appears when a panel is sized for
 * content it does not have; a view with four panels that each have real content is dense without a
 * single decorative element being added.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - Tab content gets `flex-1 min-h-0 flex flex-col` and the parent strips default spacing
 *   (`orderbook-panel.tsx:87,102`).
 * - Uppercase tracked labels at 12px, `px-2 py-1.5` chrome padding (`orderbook-panel.tsx:104`).
 * - The active tab is marked by a 1px top border and a raised fill, not by a pill: their chrome uses
 *   hairline borders throughout (`main-workspace.tsx:36,45,48`).
 * - Keyboard: digits 1..N select a view, the same "the control is the row" directness as their
 *   clickable price cell (`orderbook-row.tsx:36-45`).
 */

import { useEffect } from "react";
import { cn } from "./primitives";

export const VIEWS = [
  // FIRST, and therefore the landing surface. Task 9.2's fake win is "a beautiful landing page that
  // hides the product behind a second click", so the personal view is not a fifth tab appended at
  // the end; it is the one a cold visitor is already on.
  { id: "you", label: "You", hint: "connect, deposit, pause, withdraw" },
  { id: "decide", label: "Decide", hint: "what the agent thought, and what it rejected" },
  { id: "risk", label: "Risk", hint: "every refused candidate with its numbers, and the limits" },
  { id: "chain", label: "Chain", hint: "contracts, transactions, onchain state, learning" },
  { id: "rwa", label: "RWA", hint: "the same order judged against a crypto market and an RWA market" },
] as const;

/**
 * FOUR views. LEARN was a tab and was removed after measurement: the learning layer has
 * 2 settled forecasts, so a whole view for it measured 25.7% empty at 1600x900, and the only ways to
 * fill it would have been decoration or a fabricated statistic. Both are named failure conditions for
 * this project. Learning now sits in the CHAIN view beside the chain state it was learned from, where
 * it is a well-sized panel rather than a thin surface.
 *
 * `learn` remains a valid ViewId so a stored preference or a deep link does not break; App renders it
 * as the learning panel alone.
 */

export type ViewId = (typeof VIEWS)[number]["id"] | "learn";

export function ViewTabs({
  active,
  onSelect,
}: {
  active: ViewId;
  onSelect: (id: ViewId) => void;
}) {
  // Digit keys select a view. A terminal is driven from the keyboard; making the operator reach for
  // a mouse to change surface is the thing that makes a dense UI feel slow.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const target = e.target as HTMLElement | null;
      if (target && /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName)) return;
      const n = Number.parseInt(e.key, 10);
      if (!Number.isNaN(n) && n >= 1 && n <= VIEWS.length) {
        onSelect(VIEWS[n - 1].id);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onSelect]);

  return (
    <nav className="shrink-0 flex items-stretch border-b hairline bg-[var(--bg-base)]">
      {VIEWS.map((v, i) => {
        const isActive = v.id === active;
        return (
          <button
            key={v.id}
            type="button"
            onClick={() => onSelect(v.id)}
            title={v.hint}
            aria-current={isActive ? "page" : undefined}
            className={cn(
              "px-3 py-1 text-2xs uppercase tracking-wider border-r hairline",
              "hover:bg-[var(--fill-hover)]",
              isActive
                ? "bg-[var(--bg-raised)] text-[var(--text-strong)] border-t-2"
                : "text-[var(--text-weak)] border-t-2 border-t-transparent",
            )}
            style={isActive ? { borderTopColor: "var(--status-info)" } : undefined}
          >
            <span className="num mr-1.5 text-[var(--text-weak)]">{i + 1}</span>
            {v.label}
          </button>
        );
      })}
      {/* WHAT THIS SCREEN IS FOR, stated on the screen.
          A reader arriving cold sees a wall of numbers and has no way to know what question the
          terminal answers. The hint below names the current view's job in one sentence, so the answer
          is present rather than assumed. The keyboard hint sits after it. */}
      {/* BOTH HIDDEN BELOW THE MOBILE BREAKPOINT, and this was measured rather than guessed. At
          390x844 the five tabs consume the full row, the flex-1 container collapses to zero, and
          `truncate` does not save it: the hint and the keyboard helper were painting ON TOP of the
          last tab, a 539px-squared overlap that task 9.2's audit now reports as a defect. The
          keyboard helper is doubly pointless on a touch device, where there is no keyboard to press
          1 to 5 on. `md:` is 768px, the same breakpoint HypeTerminal pins in
          `config/layout.ts:1` as MOBILE_BREAKPOINT_PX. */}
      <div className="hidden md:flex flex-1 items-center justify-end gap-3 px-2 min-w-0">
        <span className="text-2xs text-[var(--text-weak)] truncate">
          {VIEWS.find((v) => v.id === active)?.hint}
        </span>
        <span className="shrink-0 text-2xs text-[var(--text-weak)]">
          press 1 to {VIEWS.length}
        </span>
      </div>
    </nav>
  );
}
