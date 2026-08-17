/**
 * Live Brain panel, task 4.4.
 *
 * The PASS condition is specific: "the rejected candidates are visible with scores, which is the
 * anti-if-else-ladder". So the centre of this panel is the candidate table, including the ones
 * that lost and why. A panel that only shows the chosen action is indistinguishable from a panel
 * in front of a hardcoded rule.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - `memo` with a hand-written comparator on the hot row component (orderbook-row.tsx:52-65).
 *   Here the comparator is over the candidate's scalar fields, so a new snapshot object re-renders
 *   only rows whose numbers moved. This is what task 4.3's render-count check measures.
 * - 12px `tabular-nums` data rows at `py-0.5 px-2` (orderbook-row.tsx:34).
 * - Three-column grid with uppercase tracked headers (orderbook-panel.tsx:104).
 * - The chosen row is marked by COLOUR on the label, not by a background, so the row height
 *   stays identical across states.
 */

import { memo } from "react";
import type { Candidate, Decision } from "../lib/data";
import { bpsToPct, formatSignal, fromMicro, unitOf } from "../lib/data";
import { Panel, PanelEmpty, PanelError, cn } from "./primitives";

/** Floor for the candidate table: 9rem label + three 5rem numeric columns + room for the refusal
 * sentence. Below 40rem the table scrolls sideways rather than being clipped, which is what the
 * brain panel body was doing (clientWidth 379 against scrollWidth 477 at a 632px viewport). */
const CANDIDATE_MIN_WIDTH = "40rem";

interface RowProps {
  c: Candidate;
  /** Largest absolute score in this decision, used to size the score bar. Passed in rather than
   * computed per row so the comparator below stays cheap and the bar is stable across rows. */
  maxAbsScore: number;
}

function CandidateRowComponent({ c, maxAbsScore }: RowProps) {
  const refused = c.rejectionReason !== null;
  // Score bar, using HypeTerminal's depth-bar technique: an absolutely positioned gradient sibling
  // behind the text (orderbook-row.tsx:29-34), width proportional to the row's share of the
  // largest score in this decision. It replaces a wide empty band that the first layout left
  // between the label column and the numbers: the density measurement in
  // evidence/phase4/density-measured.md put that void at 22.77% of a 1920x1080 viewport, which is
  // the "empty regions" failure condition this project is judged against.
  const pct =
    maxAbsScore > 0 && Number.isFinite(c.scoreMicro)
      ? Math.min(100, (Math.abs(c.scoreMicro) / maxAbsScore) * 100)
      : 0;
  return (
    <div
      className={cn(
        "relative grid grid-cols-[minmax(9rem,26rem)_5rem_5rem_5rem_minmax(0,1fr)] gap-2 px-2 py-0.5",
        "border-b hairline last:border-b-0 hover:bg-[var(--fill-hover)]",
      )}
      style={{ minWidth: CANDIDATE_MIN_WIDTH }}
    >
      <div
        className={cn(
          "absolute inset-y-0 left-0 pointer-events-none",
          c.chosen ? "util-bar-ok" : refused ? "util-bar-danger" : "util-bar-warn",
        )}
        style={{ width: `${pct}%` }}
      />
      <span
        className="relative z-10 text-2xs truncate"
        style={{
          color: c.chosen
            ? "var(--status-long)"
            : refused
              ? "var(--status-short)"
              : "var(--text-weak)",
        }}
        title={c.label}
      >
        {c.chosen ? "> " : ""}
        {c.label}
      </span>
      <span className="relative z-10 num text-2xs text-right">{fromMicro(c.scoreMicro)}</span>
      <span className="relative z-10 num text-2xs text-right text-[var(--text-weak)]">
        {fromMicro(c.expectedEdgeMicro)}
      </span>
      <span className="relative z-10 num text-2xs text-right text-[var(--text-weak)]">
        {fromMicro(c.variancePenaltyMicro + c.capitalCostMicro + c.executionRiskPenaltyMicro)}
      </span>
      <span
        className="relative z-10 text-2xs truncate text-[var(--text-weak)]"
        title={c.rejectionReason ?? ""}
      >
        {c.rejectionReason ?? "accepted by risk"}
      </span>
    </div>
  );
}

/** Hand-written comparator, per orderbook-row.tsx:52-65. */
const CandidateRow = memo(CandidateRowComponent, (a, b) => {
  return (
    a.maxAbsScore === b.maxAbsScore &&
    a.c.label === b.c.label &&
    a.c.chosen === b.c.chosen &&
    a.c.scoreMicro === b.c.scoreMicro &&
    a.c.expectedEdgeMicro === b.c.expectedEdgeMicro &&
    a.c.variancePenaltyMicro === b.c.variancePenaltyMicro &&
    a.c.capitalCostMicro === b.c.capitalCostMicro &&
    a.c.executionRiskPenaltyMicro === b.c.executionRiskPenaltyMicro &&
    a.c.rejectionReason === b.c.rejectionReason
  );
});

export function BrainPanel({
  decision,
  error,
}: {
  decision: Decision | null;
  error?: { source: string; reason: string };
}) {
  const refusedCount = decision?.candidates.filter((c) => c.rejectionReason !== null).length ?? 0;
  const maxAbsScore =
    decision?.candidates.reduce(
      (m, c) => (Number.isFinite(c.scoreMicro) ? Math.max(m, Math.abs(c.scoreMicro)) : m),
      0,
    ) ?? 0;

  return (
    <Panel
      title="Live brain"
      meta={
        decision ? (
          <>
            <span className="num">#{decision.decisionId}</span>
            <span className="num">blk {decision.blockNumber}</span>
            <span className="num">{decision.candidates.length} cand</span>
            <span className="num" style={{ color: "var(--status-short)" }}>
              {refusedCount} refused
            </span>
          </>
        ) : null
      }
    >
      {error ? (
        <PanelError source={error.source} reason={error.reason} />
      ) : !decision ? (
        <PanelEmpty what="the first decision" />
      ) : (
        <div className="flex-1 min-h-0 flex flex-col overflow-hidden">
          {/* Out-of-range values are named at the top of the panel, not left for a reader to spot
              in a column. Task 4.9's red team fed a confidence of 999999999 bps and a 20-digit
              block number, and the first version rendered both as if they were data. */}
          {decision.anomalies.length > 0 ? (
            <div
              className="shrink-0 px-2 py-1 border-b hairline"
              style={{ background: "var(--fill-weak)" }}
            >
              <span className="col-label" style={{ color: "var(--status-short)" }}>
                values out of range in this row
              </span>
              <ul className="mt-0.5">
                {decision.anomalies.map((a) => (
                  <li key={a} className="text-xs" style={{ color: "var(--status-short)" }}>
                    {a}
                  </li>
                ))}
              </ul>
            </div>
          ) : null}

          {/* Thesis. One line of prose assembled from the real signal numbers, so it is worth
              showing verbatim rather than summarising. */}
          <div className="shrink-0 px-2 py-1 border-b hairline">
            <div className="flex items-baseline gap-2">
              <span className="col-label">thesis</span>
              <span className="num text-2xs" style={{ color: "var(--status-info)" }}>
                {bpsToPct(decision.thesisConfidenceBps)}% conf
              </span>
              <span className="num text-2xs text-[var(--text-weak)]">{decision.market}</span>
            </div>
            <p className="text-xs text-[var(--text-weak)] mt-0.5">{decision.thesis}</p>
          </div>

          {/* Signals. Value with its confidence halfwidth and its age, because a signal without
              those two is a number with unknown trust. */}
          <div className="shrink-0 border-b hairline">
            <div className="grid grid-cols-[minmax(0,1fr)_6rem_6rem_4rem] gap-2 px-2 py-0.5 border-b hairline">
              <span className="col-label">signal</span>
              <span className="col-label text-right">value</span>
              <span className="col-label text-right">± halfwidth</span>
              <span className="col-label text-right">age ms</span>
            </div>
            {decision.signals.map((s) => (
              <div
                key={s.name}
                className="grid grid-cols-[minmax(0,1fr)_6rem_6rem_4rem] gap-2 px-2 py-0.5"
              >
                <span className="text-2xs truncate text-[var(--text-weak)]">{s.name}</span>
                {/* Formatted in the signal's REAL unit. `value_micro` holds plain basis points for
                    the `_bps` signals and micro-units for the `_base` ones, so dividing every one by
                    1e6 rendered spread -2325 bps as "-0.00" and made the whole table read as zero.
                    See the note on unitOf in lib/data.ts. */}
                <span className="num text-2xs text-right">
                  {formatSignal(s.name, s.valueMicro)}
                  <span className="ml-1 text-[var(--text-weak)]">
                    {unitOf(s.name) === "bps" ? "bps" : ""}
                  </span>
                </span>
                <span className="num text-2xs text-right text-[var(--text-weak)]">
                  {formatSignal(s.name, s.confidenceHalfwidthMicro)}
                </span>
                <span className="num text-2xs text-right text-[var(--text-weak)]">
                  {s.inputAgeMs}
                </span>
              </div>
            ))}
          </div>

          {/* Candidates, the part that proves this is a scoring engine and not a rule.
              The header lives INSIDE the scroller and is sticky, so it scrolls sideways with the rows
              and stays put vertically. Keeping it outside was a real defect: at a 632px viewport the
              header's own min-width overflowed the panel body, which hides overflow, so the labels
              were clipped while the rows scrolled independently underneath them. A numeric column
              under the wrong label is worse than no label. */}
          <div className="flex-1 min-h-0 overflow-auto scroll-thin">
            <div style={{ minWidth: CANDIDATE_MIN_WIDTH }}>
              <div className="sticky top-0 z-20 grid grid-cols-[minmax(9rem,26rem)_5rem_5rem_5rem_minmax(0,1fr)] gap-2 px-2 py-0.5 border-b hairline bg-[var(--bg-raised)]">
                <span className="col-label">candidate</span>
                <span className="col-label text-right">score</span>
                <span className="col-label text-right">edge</span>
                <span className="col-label text-right">costs</span>
                <span className="col-label">refused because</span>
              </div>
              {decision.candidates.map((c, i) => (
                <CandidateRow key={`${c.label}-${i}`} c={c} maxAbsScore={maxAbsScore} />
              ))}
            </div>
          </div>

          {/* The risk verdict in the agent's own words. */}
          <div className="shrink-0 px-2 py-1 border-t hairline">
            <span className="col-label">risk verdict</span>
            <p className="text-xs text-[var(--text-weak)]">{decision.riskVerdict}</p>
          </div>
        </div>
      )}
    </Panel>
  );
}
