/**
 * Journal panel: the decision log, one row per decision.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - Row count derived from MEASURED HEIGHT with a ResizeObserver, then used as a DATA parameter
 *   rather than a CSS overflow (use-orderbook-rows.ts:3-26, and orderbook-panel.tsx:52-56 passes
 *   `visibleRows` into `processLevels`). The panel never renders rows it will clip, which is why
 *   their panels have no dead strip at the bottom.
 * - `memo` with a hand-written comparator on the row (orderbook-row.tsx:52-65).
 * - 12px tabular-nums rows at py-0.5 px-2, uppercase tracked headers (orderbook-row.tsx:34,
 *   orderbook-panel.tsx:104).
 * - Selection is by row click, the same "the row is the control" idea as their clickable price
 *   cell (orderbook-row.tsx:36-45).
 */

import { memo, useCallback, useEffect, useState } from "react";
import { PANEL_LAYOUT } from "../config/layout";
import type { ChainConfig, Decision } from "../lib/data";
import { blockLabel, bpsToPct } from "../lib/data";
import { Panel, PanelEmpty, PanelError, cn } from "./primitives";

/** Sum of the row's fixed tracks plus a floor for the flexible action column.
 *
 * 3 + 5.5 + 4 + 3 + 5 = 20.5rem of fixed tracks, and the action column needs room to be worth
 * showing, so the table's minimum is 34rem. Below that the row scrolls sideways rather than
 * resolving the action column to zero width, which is what it did before and it silently removed
 * the most important field in the row. */
const JOURNAL_MIN_WIDTH = "34rem";

/**
 * Height-derived row count PLUS a scroll window, task 5.3.
 *
 * The first version computed how many rows fit and rendered exactly that many, leaving the rest
 * unreachable: 43 rows in the file, 20 on screen, no way to reach decision 1. A feed you cannot
 * scroll is not a feed, and that was a real defect rather than a missing nicety.
 *
 * This keeps the height-derived count, which is HypeTerminal's idea of making the row count a DATA
 * parameter rather than a CSS overflow (`use-orderbook-rows.ts:3-26`, consumed at
 * `orderbook-panel.tsx:52-56`), and adds windowed rendering: a spacer of `total * ROW_HEIGHT` gives
 * the scrollbar its true length while only the visible slice plus OVERSCAN rows are mounted. Their
 * equivalent constant pairing is `TOKEN_SELECTOR_ROW_HEIGHT_PX` with `TOKEN_SELECTOR_OVERSCAN`
 * (their config/layout.ts:29-30).
 *
 * Their ROW_HEIGHT is 19 for a 16px line box; ours is 20, a 16px line box with 2px padding each side.
 */
function useWindowedRows(total: number) {
  const { ROW_HEIGHT_PX, MIN_ROWS, MAX_ROWS, OVERSCAN } = PANEL_LAYOUT.JOURNAL;
  // Explicit `<number>`: PANEL_LAYOUT is `as const`, so without it the state type narrows to the
  // literal 40 and every computed row count is a type error.
  const [visible, setVisible] = useState<number>(MAX_ROWS);
  const [start, setStart] = useState(0);
  const [node, setNode] = useState<HTMLDivElement | null>(null);
  const ref = useCallback((el: HTMLDivElement | null) => setNode(el), []);

  useEffect(() => {
    if (!node) return;
    const measure = () => {
      const h = node.clientHeight;
      if (h === 0) return;
      const n = Math.floor(h / ROW_HEIGHT_PX);
      setVisible(Math.min(MAX_ROWS, Math.max(MIN_ROWS, n)));
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
    visible,
    padTopPx: start * ROW_HEIGHT_PX,
    totalHeightPx: total * ROW_HEIGHT_PX,
  } as const;
}

interface RowProps {
  d: Decision;
  selected: boolean;
  explorerBase: string;
  onSelect: (id: number) => void;
}

function RowComponent({ d, selected, explorerBase, onSelect }: RowProps) {
  const isTake = d.action.startsWith("take");
  return (
    <button
      type="button"
      onClick={() => onSelect(d.decisionId)}
      className={cn(
        "w-full text-left grid grid-cols-[3rem_5.5rem_minmax(0,1fr)_4rem_3rem_5rem] gap-2 px-2 py-0.5",
        "border-b hairline hover:bg-[var(--fill-hover)]",
        selected && "bg-[var(--fill-press)]",
      )}
      style={{ height: `${PANEL_LAYOUT.JOURNAL.ROW_HEIGHT_PX}px` }}
    >
      <span className="num text-2xs text-[var(--text-weak)]">{d.decisionId}</span>
      <span
        className="num text-2xs"
        style={{ color: d.anomalies.length > 0 ? "var(--status-short)" : "var(--text-weak)" }}
        title={d.anomalies.join("; ")}
      >
        {blockLabel(d.blockNumber)}
      </span>
      <span
        className="text-2xs truncate"
        style={{
          color: d.isBaseline
            ? "var(--status-warn)"
            : isTake
              ? "var(--status-long)"
              : "var(--text-weak)",
        }}
        title={d.action}
      >
        {d.isBaseline ? "[baseline] " : ""}
        {d.anomalies.length > 0 ? "[!] " : ""}
        {d.action}
      </span>
      {/* The percent sign is appended only when the value IS a percentage. "invalid%" reads as a
          unit on a number rather than as a rejection, which was the first version's mistake. */}
      <span className="num text-2xs text-right text-[var(--text-weak)]">
        {(() => {
          const v = bpsToPct(d.thesisConfidenceBps, 1);
          return v === "invalid" || v === "—" ? v : `${v}%`;
        })()}
      </span>
      <span className="num text-2xs text-right text-[var(--text-weak)]">
        {d.candidates.length}
      </span>
      <span className="num text-2xs text-right truncate">
        {d.txHash ? (
          <a
            href={`${explorerBase}${d.txHash}`}
            target="_blank"
            rel="noreferrer noopener"
            style={{ color: "var(--status-info)" }}
            onClick={(e) => e.stopPropagation()}
          >
            {d.txHash.slice(0, 8)}
          </a>
        ) : (
          <span className="text-[var(--text-weak)]">no tx</span>
        )}
      </span>
    </button>
  );
}

const Row = memo(
  RowComponent,
  (a, b) =>
    a.selected === b.selected &&
    a.explorerBase === b.explorerBase &&
    a.d.decisionId === b.d.decisionId &&
    a.d.blockNumber === b.d.blockNumber &&
    a.d.action === b.d.action &&
    a.d.thesisConfidenceBps === b.d.thesisConfidenceBps &&
    a.d.candidates.length === b.d.candidates.length &&
    a.d.txHash === b.d.txHash &&
    a.d.isBaseline === b.d.isBaseline &&
    a.d.anomalies.length === b.d.anomalies.length,
);

export function JournalPanel({
  decisions,
  chain,
  selectedId,
  onSelect,
  error,
  totalLines,
}: {
  decisions: Decision[];
  chain: ChainConfig | null;
  selectedId: number | null;
  onSelect: (id: number) => void;
  error?: { source: string; reason: string };
  totalLines: number | null;
}) {
  const win = useWindowedRows(decisions.length);
  const explorerBase = chain?.explorerBase ?? "";
  const shown = decisions.slice(win.start, win.start + win.count);

  return (
    <Panel
      title="Decision journal"
      minHeightPx={
        decisions.length === 0
          ? PANEL_LAYOUT.JOURNAL.emptyMinHeightPx
          : PANEL_LAYOUT.JOURNAL.minHeightPx
      }
      meta={
        // See the note in risk-panel.tsx: with the source unavailable, a count of 0 is a claim,
        // not a measurement.
        error ? (
          <span className="num">—</span>
        ) : (
          <>
            <span className="num" title="rendered / total in the window">
              {shown.length} mounted of {decisions.length}
            </span>
            {totalLines !== null ? <span className="num">{totalLines} lines</span> : null}
          </>
        )
      }
    >
      {error ? (
        <PanelError source={error.source} reason={error.reason} />
      ) : decisions.length === 0 ? (
        <PanelEmpty what="the first journal row" />
      ) : (
        <div className="flex-1 min-h-0 flex flex-col overflow-hidden">

          {/* The scroll window. The outer div scrolls; the inner spacer is the FULL height of the
              dataset so the scrollbar reports the real length, and only the visible slice plus
              overscan is mounted. `translateY` positions that slice instead of rendering thousands
              of empty rows above it. */}
          <div ref={win.ref} className="flex-1 min-h-0 overflow-auto scroll-thin">
            <div style={{ minWidth: JOURNAL_MIN_WIDTH }}>
              {/* Header inside the scroller and sticky: it scrolls sideways with the rows so a column
                  label always sits above its own numbers, and stays fixed vertically. */}
              <div
                className="sticky top-0 z-20 grid grid-cols-[3rem_5.5rem_minmax(0,1fr)_4rem_3rem_5rem] gap-2 px-2 py-0.5 border-b hairline bg-[var(--bg-raised)]"
              >
                <span className="col-label">id</span>
                <span className="col-label">block</span>
                <span className="col-label">action</span>
                <span className="col-label text-right">conf</span>
                <span className="col-label text-right">cand</span>
                <span className="col-label text-right">tx</span>
              </div>
              <div style={{ height: `${win.totalHeightPx}px`, position: "relative" }}>
                <div style={{ transform: `translateY(${win.padTopPx}px)` }}>
                {shown.map((d) => (
                  <Row
                    key={d.decisionId}
                    d={d}
                    selected={selectedId === d.decisionId}
                    explorerBase={explorerBase}
                    onSelect={onSelect}
                  />
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </Panel>
  );
}
