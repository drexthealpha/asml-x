/**
 * Risk panel, task 4.5.
 *
 * PASS condition: "at least one utilisation bar visibly near its limit during the demo run,
 * otherwise the panel is decoration". So the bars are computed from the REAL journal: refusal
 * reasons carry the numbers that caused them (`OrderNotionalTooLarge { got, limit }` in
 * crates/risk-engine), and the highest observed `got` against its `limit` is a real utilisation
 * reading rather than a made-up gauge.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - Utilisation bars use the depth-bar technique: an absolutely positioned gradient sibling with
 *   the numbers above it (orderbook-row.tsx:29-34), colour derived from a token with
 *   `oklch(from ...)` (styles.css:506-517).
 * - Refusal counts are grouped and shown with their reason string, which is the same "explain in
 *   place" idea as their error copy sitting in the panel body (orderbook-panel.tsx:151-153).
 */

import { useMemo } from "react";
import type { Decision } from "../lib/data";
import { fromMicro } from "../lib/data";
import { Panel, PanelEmpty, PanelError, UtilisationBar } from "./primitives";

/** Refusal strings from crates/risk-engine carry their numbers. Pull them back out.
 *
 * The parse is deliberately narrow: it matches the two numeric fields every limit refusal
 * carries. If the Rust variant's Debug format changes, this stops matching and the panel shows
 * NO bars rather than wrong ones, which is the correct failure direction. */
const REFUSAL_NUMBERS = /\{\s*got:\s*(-?\d+),\s*limit:\s*(-?\d+)/;

/** WEI_PER_MICRO is 1e12 (crates/market-intel/src/lib.rs:60). A micro-unit notional in this demo
 * is at most tens of millions, so a `got` above this is a wei value that skipped the boundary
 * conversion. The 9 Aug journal has 40 of them, all pre-dating the fix. Full finding:
 * evidence/phase4/journal-provenance.md, detector: scripts/77-journal-scale-audit.sh */
const WEI_SCALE_SUSPECT = 1e12;

/** The engine prefixes its reason with "risk refused: " and appends the fields in braces, so the
 * variant name is between the first ": " and the first "{". Splitting on whitespace gives "risk",
 * and splitting on the LAST colon gives a fragment of the numbers: both were tried and both were
 * wrong. */
function refusalName(reason: string): string {
  const body = reason.includes(": ") ? reason.slice(reason.indexOf(": ") + 2) : reason;
  const name = body.split("{")[0]?.trim();
  return name && name.length > 0 ? name : reason;
}

interface Util {
  label: string;
  got: number;
  limit: number;
}

interface UtilResult {
  utils: Util[];
  /** Refusals rejected for an implausible scale. Reported, never clamped: a bar reading 1.2e25%
   * would be worse than no bar, and silently dividing by 1e12 to make it look sane would be
   * inventing data. */
  scaleAnomalies: number;
}

function extractUtilisation(decisions: Decision[]): UtilResult {
  const worst = new Map<string, Util>();
  let scaleAnomalies = 0;
  for (const d of decisions) {
    for (const c of d.candidates) {
      const r = c.rejectionReason;
      if (!r) continue;
      const m = REFUSAL_NUMBERS.exec(r);
      if (!m) continue;
      const got = Number(m[1]);
      const limit = Number(m[2]);
      if (!Number.isFinite(got) || !Number.isFinite(limit) || limit <= 0) continue;
      if (got > WEI_SCALE_SUSPECT) {
        scaleAnomalies += 1;
        continue;
      }
      const name = refusalName(r);
      const prev = worst.get(name);
      if (!prev || got > prev.got) worst.set(name, { label: name, got, limit });
    }
  }
  return {
    utils: [...worst.values()].sort((a, b) => b.got / b.limit - a.got / a.limit),
    scaleAnomalies,
  };
}

function countRefusals(decisions: Decision[]): Array<[string, number]> {
  const counts = new Map<string, number>();
  for (const d of decisions) {
    for (const c of d.candidates) {
      if (!c.rejectionReason) continue;
      const name = refusalName(c.rejectionReason);
      counts.set(name, (counts.get(name) ?? 0) + 1);
    }
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
}

export function RiskPanel({
  decisions,
  error,
}: {
  decisions: Decision[];
  error?: { source: string; reason: string };
}) {
  // Agent decisions only. Baseline control rows are excluded here for the same reason they were
  // excluded from the river benchmark in task 1.14: they are not the agent's behaviour, and
  // mixing them in inflates every statistic computed from them.
  const agent = useMemo(() => decisions.filter((d) => !d.isBaseline), [decisions]);
  const { utils, scaleAnomalies } = useMemo(() => extractUtilisation(agent), [agent]);
  const refusals = useMemo(() => countRefusals(agent), [agent]);
  const totalRefusals = refusals.reduce((n, [, c]) => n + c, 0);

  return (
    <Panel
      title="Risk"
      meta={
        // With the source unavailable these counts must NOT render as 0. A zero is a number a
        // reader believes, and "0 refusals" next to an unreadable journal is a false statement
        // about the agent. Task 4.7's no-data proof caught exactly this in the panel headers.
        error ? (
          <span className="num">—</span>
        ) : (
          <>
            <span className="num">{agent.length} decisions</span>
            <span className="num" style={{ color: "var(--status-short)" }}>
              {totalRefusals} refusals
            </span>
          </>
        )
      }
    >
      {error ? (
        <PanelError source={error.source} reason={error.reason} />
      ) : agent.length === 0 ? (
        <PanelEmpty what="a decision to evaluate" />
      ) : (
        // Scrolls. This was `overflow-hidden` with stacked sections inside and no scroll region, so
        // once the refusal-reason list grew past the box the rest was unreachable: measured
        // clientHeight 458 against scrollHeight 565 at a 632px viewport.
        <div className="flex-1 min-h-0 flex flex-col overflow-y-auto scroll-thin">
          <div className="shrink-0 grid grid-cols-[1fr_auto_auto] gap-2 px-2 py-0.5 border-b hairline">
            <span className="col-label">peak observed utilisation</span>
            <span className="col-label text-right">got / limit</span>
            <span className="col-label text-right w-12">pct</span>
          </div>

          {utils.length === 0 ? (
            <div className="px-2 py-2 flex flex-col gap-1">
              <p className="text-xs text-[var(--text-weak)]">
                No limit refusal in the loaded window carried usable numbers, so no utilisation is
                shown. This panel does not draw a bar it cannot source.
              </p>
              {scaleAnomalies > 0 ? (
                <p className="text-xs" style={{ color: "var(--status-warn)" }}>
                  {scaleAnomalies} refusal(s) reported a notional above 1e12 micro-units, which is
                  a wei value that skipped the boundary conversion. This journal predates that fix.
                  See evidence/phase4/journal-provenance.md and run
                  scripts/77-journal-scale-audit.sh.
                </p>
              ) : null}
            </div>
          ) : (
            <div className="shrink-0">
              {utils.map((u) => (
                <UtilisationBar
                  key={u.label}
                  label={u.label}
                  pct={(u.got / u.limit) * 100}
                  detail={`${fromMicro(u.got)} / ${fromMicro(u.limit)}`}
                />
              ))}
            </div>
          )}

          <div className="shrink-0 grid grid-cols-[1fr_auto] gap-2 px-2 py-0.5 border-y hairline mt-1">
            <span className="col-label">refusals by reason</span>
            <span className="col-label text-right">count</span>
          </div>
          <div className="flex-1 min-h-0 overflow-y-auto scroll-thin">
            {refusals.map(([name, count]) => (
              <div
                key={name}
                className="grid grid-cols-[1fr_auto] gap-2 px-2 py-0.5 border-b hairline last:border-b-0"
              >
                <span className="text-2xs truncate text-[var(--text-weak)]" title={name}>
                  {name}
                </span>
                <span className="num text-2xs text-right">{count}</span>
              </div>
            ))}
          </div>

          <div className="shrink-0 px-2 py-1 border-t hairline">
            <p className="text-xs text-[var(--text-weak)]">
              Utilisation is read back from refusals the engine actually issued. The binding limits
              live in crates/risk-engine and onchain in RiskGuard; nothing here is a second source
              of truth for a limit.
            </p>
          </div>
        </div>
      )}
    </Panel>
  );
}
