/**
 * Refusal ledger: every candidate the engine refused, across every loaded decision.
 *
 * WHY THIS PANEL EXISTS, and it is a density argument backed by a measurement. Splitting the terminal
 * into views left the Risk view 41% empty at 1600x900, because the risk summary is short: a handful
 * of reason totals and two utilisation bars. The wrong fix is a decorative chart. The right fix is
 * that this agent HAS 2,236 refusals recorded in the journal and the UI was showing only their
 * counts. Those rows are the single richest honest dataset in the product, and they are exactly the
 * thing the project claims: the agent refuses, with numbers, for stated reasons.
 *
 * It is also the anti-if-else-ladder evidence in its strongest form. A panel showing what was chosen
 * proves nothing about whether a decision was made. A ledger of 2,236 rejections, each with its score
 * and the limit it breached, cannot be produced by a hardcoded rule.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - Windowed rows with an overscan constant, the same technique as the journal feed
 *   (`use-orderbook-rows.ts:3-26`, `config/layout.ts:29-30`).
 * - 12px `tabular-nums` rows at `py-0.5 px-2`, uppercase tracked column labels
 *   (`orderbook-row.tsx:34`, `orderbook-panel.tsx:104`).
 * - Gradient bar behind the row to encode how far past the limit a candidate was
 *   (`orderbook-row.tsx:29-34`).
 * - `memo` with a hand-written comparator (`orderbook-row.tsx:52-65`).
 * - Filter chips are plain buttons with hairline borders, not pills (`main-workspace.tsx:36,45,48`).
 */

import { memo, useCallback, useEffect, useMemo, useState } from "react";
import { PANEL_LAYOUT } from "../config/layout";
import type { Decision } from "../lib/data";
import { fromMicro } from "../lib/data";
import { Panel, PanelEmpty, PanelError, cn } from "./primitives";

/** 3.5 + 5.5 + 15 + 6 + 6 = 36rem of fixed tracks, plus room for the engine's refusal sentence,
 * which is the widest field and the reason the ledger exists. 52rem minimum. */
const LEDGER_MIN_WIDTH = "52rem";

interface RefusalRow {
  decisionId: number;
  blockNumber: number;
  label: string;
  reason: string;
  reasonName: string;
  scoreMicro: number;
  /** Present only for limit refusals, which carry `got` and `limit` in the reason text. */
  gotMicro: number | null;
  limitMicro: number | null;
}

/** `MarketNotionalTooLarge { got: 52960000, limit: 50000000 }` and friends.
 *
 * The numbers are parsed OUT of the reason string rather than being re-derived, so what the panel
 * shows is what the engine said. If the engine's formatting changes this stops matching and the row
 * degrades to reason-only, which is the safe direction: no invented numbers. */
const LIMIT_NUMBERS = /got:\s*(-?\d+),\s*limit:\s*(-?\d+)/;

function reasonNameOf(reason: string): string {
  const body = reason.includes(": ") ? reason.slice(reason.indexOf(": ") + 2) : reason;
  const name = body.split("{")[0].trim();
  return name || reason;
}

function RowComponent({ r }: { r: RefusalRow }) {
  // How far past the limit, as a share of the limit, capped at 100% for the bar only. The printed
  // number is never capped.
  const overPct =
    r.gotMicro !== null && r.limitMicro !== null && r.limitMicro > 0
      ? Math.min(100, ((r.gotMicro - r.limitMicro) / r.limitMicro) * 100)
      : 0;
  const isLimit = r.gotMicro !== null;
  return (
    <div
      className="relative grid grid-cols-[3.5rem_5.5rem_15rem_6rem_6rem_minmax(0,1fr)] gap-2 px-2 py-0.5 border-b hairline last:border-b-0 hover:bg-[var(--fill-hover)]"
      style={{ height: `${PANEL_LAYOUT.JOURNAL.ROW_HEIGHT_PX}px` }}
    >
      {overPct > 0 ? (
        <div
          className="absolute inset-y-0 left-0 pointer-events-none util-bar-danger"
          style={{ width: `${overPct}%` }}
        />
      ) : null}
      <span className="relative z-10 num text-2xs text-[var(--text-weak)]">{r.decisionId}</span>
      <span className="relative z-10 num text-2xs text-[var(--text-weak)]">{r.blockNumber}</span>
      <span className="relative z-10 text-2xs truncate text-[var(--text-weak)]" title={r.label}>
        {r.label}
      </span>
      <span className="relative z-10 num text-2xs text-right">
        {r.gotMicro !== null ? fromMicro(r.gotMicro) : ""}
      </span>
      <span className="relative z-10 num text-2xs text-right text-[var(--text-weak)]">
        {r.limitMicro !== null ? fromMicro(r.limitMicro) : fromMicro(r.scoreMicro)}
      </span>
      {/* The engine's OWN refusal text, in full rather than as a shortened name. It is the longest
          field, so it takes the flexible column: a 1fr column holding a 12-character name is what
          left a 248x848 void here. */}
      <span
        className="relative z-10 text-2xs truncate"
        style={{ color: isLimit ? "var(--status-short)" : "var(--text-weak)" }}
        title={r.reason}
      >
        {r.reason}
      </span>
    </div>
  );
}

const Row = memo(
  RowComponent,
  (a, b) =>
    a.r.decisionId === b.r.decisionId &&
    a.r.label === b.r.label &&
    a.r.reason === b.r.reason &&
    a.r.gotMicro === b.r.gotMicro &&
    a.r.limitMicro === b.r.limitMicro &&
    a.r.scoreMicro === b.r.scoreMicro,
);

function useWindow(total: number) {
  const { ROW_HEIGHT_PX, MIN_ROWS, MAX_ROWS, OVERSCAN } = PANEL_LAYOUT.JOURNAL;
  const [visible, setVisible] = useState<number>(MAX_ROWS);
  const [start, setStart] = useState(0);
  const [node, setNode] = useState<HTMLDivElement | null>(null);
  const ref = useCallback((el: HTMLDivElement | null) => setNode(el), []);
  useEffect(() => {
    if (!node) return;
    const measure = () => {
      const h = node.clientHeight;
      if (h === 0) return;
      setVisible(Math.min(MAX_ROWS, Math.max(MIN_ROWS, Math.floor(h / ROW_HEIGHT_PX))));
      setStart(Math.max(0, Math.floor(node.scrollTop / ROW_HEIGHT_PX) - OVERSCAN));
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(node);
    node.addEventListener("scroll", measure, { passive: true });
    return () => {
      ro.disconnect();
      node.removeEventListener("scroll", measure);
    };
  }, [node, ROW_HEIGHT_PX, MIN_ROWS, MAX_ROWS, OVERSCAN]);
  return {
    ref,
    start,
    count: Math.max(0, Math.min(total - start, visible + OVERSCAN * 2)),
    padTopPx: start * ROW_HEIGHT_PX,
    totalHeightPx: total * ROW_HEIGHT_PX,
  } as const;
}

export function RefusalLedger({
  decisions,
  error,
}: {
  decisions: Decision[];
  error?: { source: string; reason: string };
}) {
  const [only, setOnly] = useState<"limits" | "all">("limits");

  const all = useMemo<RefusalRow[]>(() => {
    const out: RefusalRow[] = [];
    for (const d of decisions) {
      if (d.isBaseline) continue;
      for (const c of d.candidates) {
        if (!c.rejectionReason) continue;
        const m = LIMIT_NUMBERS.exec(c.rejectionReason);
        out.push({
          decisionId: d.decisionId,
          blockNumber: d.blockNumber,
          label: c.label,
          reason: c.rejectionReason,
          reasonName: reasonNameOf(c.rejectionReason),
          scoreMicro: c.scoreMicro,
          gotMicro: m ? Number(m[1]) : null,
          limitMicro: m ? Number(m[2]) : null,
        });
      }
    }
    return out;
  }, [decisions]);

  // Default to LIMIT refusals. "lower score" is 1,956 of the 2,236 rows and it is not a risk event:
  // it means another candidate scored higher, which is the engine working normally. Showing it first
  // would bury the 280 rows where a limit actually bound. The toggle makes the choice visible rather
  // than hiding the majority silently.
  const rows = useMemo(
    () => (only === "limits" ? all.filter((r) => r.gotMicro !== null) : all),
    [all, only],
  );

  const limitCount = useMemo(() => all.filter((r) => r.gotMicro !== null).length, [all]);
  const win = useWindow(rows.length);
  const shown = rows.slice(win.start, win.start + win.count);

  const worst = useMemo(() => {
    let w: RefusalRow | null = null;
    for (const r of all) {
      if (r.gotMicro === null || r.limitMicro === null || r.limitMicro <= 0) continue;
      const over = (r.gotMicro - r.limitMicro) / r.limitMicro;
      if (!w || over > (w.gotMicro! - w.limitMicro!) / w.limitMicro!) w = r;
    }
    return w;
  }, [all]);

  if (error) {
    return (
      <Panel title="Refusal ledger">
        <PanelError source={error.source} reason={error.reason} />
      </Panel>
    );
  }
  if (all.length === 0) {
    return (
      <Panel title="Refusal ledger">
        <PanelEmpty what="a refused candidate" />
      </Panel>
    );
  }

  return (
    <Panel
      title="Refusal ledger"
      meta={
        <>
          <span className="num">{rows.length} shown</span>
          <span className="num">{limitCount} by a limit</span>
          <span className="num">{all.length} total</span>
        </>
      }
    >
      <div className="shrink-0 flex items-center gap-1 px-2 py-0.5 border-b hairline">
        {(
          [
            ["limits", `limit refusals (${limitCount})`],
            ["all", `every refusal (${all.length})`],
          ] as const
        ).map(([id, label]) => (
          <button
            key={id}
            type="button"
            onClick={() => setOnly(id)}
            className={cn(
              "px-1.5 py-0 text-2xs uppercase tracking-wider border hairline",
              only === id
                ? "bg-[var(--bg-raised)] text-[var(--text-strong)]"
                : "text-[var(--text-weak)] hover:bg-[var(--fill-hover)]",
            )}
          >
            {label}
          </button>
        ))}
        {worst ? (
          <span className="ml-auto text-2xs text-[var(--text-weak)]">
            worst breach: {worst.reasonName} at{" "}
            <span className="num">{fromMicro(worst.gotMicro ?? 0)}</span> against{" "}
            <span className="num">{fromMicro(worst.limitMicro ?? 0)}</span> on decision{" "}
            <span className="num">{worst.decisionId}</span>
          </span>
        ) : null}
      </div>

      <div ref={win.ref} className="flex-1 min-h-0 overflow-auto scroll-thin">
        <div style={{ minWidth: LEDGER_MIN_WIDTH }}>
          {/* Sticky header inside the scroller, so the labels track their own columns horizontally. */}
          <div className="sticky top-0 z-20 grid grid-cols-[3.5rem_5.5rem_15rem_6rem_6rem_minmax(0,1fr)] gap-2 px-2 py-0.5 border-b hairline bg-[var(--bg-raised)]">
            <span className="col-label">dec</span>
            <span className="col-label">block</span>
            <span className="col-label">candidate refused</span>
            <span className="col-label text-right">got</span>
            <span className="col-label text-right">limit / score</span>
            <span className="col-label">reason, as the engine reported it</span>
          </div>
          <div style={{ height: `${win.totalHeightPx}px`, position: "relative" }}>
            <div style={{ transform: `translateY(${win.padTopPx}px)` }}>
              {shown.map((r, i) => (
                <Row key={`${r.decisionId}-${r.label}-${win.start + i}`} r={r} />
              ))}
            </div>
          </div>
        </div>
      </div>

      <p className="shrink-0 px-2 py-1 text-xs text-[var(--text-weak)] border-t hairline">
        Every row is a candidate the risk engine refused, with the numbers it reported. `got` and
        `limit` are parsed from the engine's own refusal text, not recomputed here, so a change in the
        engine's formatting degrades a row to reason-only rather than to a wrong number.
      </p>
    </Panel>
  );
}
