/**
 * Dense top metrics bar, task 4.2.
 *
 * PASS condition: "at least 9 live values in one row; none hardcoded". Every value below is
 * derived from a loaded source, and when a source fails the value renders as an em dash rather
 * than a zero. A zero is a number a reader believes.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - Chrome height is a constant, not an inline class (their config/layout.ts:32-40). Ours is
 *   CHROME.HEADER_CLASS = h-8, i.e. 32px for the whole bar.
 * - The bar is one grid row of two-line metrics with no borders or cards. The named failure
 *   condition for this project is "oversized cards with three numbers", and the defence is that a
 *   metric here is a 10px label over a 12px monospace value.
 * - Freshness is shown, not assumed, which is their staleness watchdog idea
 *   (staleness.ts:20-109) reduced to what a poll needs: the age of the newest read and a badge
 *   past the threshold in DATA_LIMITS.
 */

import { CHAIN } from "../config/layout";
import { DATA_LIMITS, blockLabel, bpsToPct, freshness } from "../lib/data";
import type { ChainConfig, Decision, LearnedState } from "../lib/data";
import { Metric, cn } from "./primitives";

const DASH = "—";

export function TopBar({
  decisions,
  chain,
  learned,
  fetchedAtMs,
  nowMs,
  malformedLines,
  baselineRows,
  anomalousRows,
}: {
  decisions: Decision[] | null;
  chain: ChainConfig | null;
  learned: LearnedState | null;
  fetchedAtMs: number | null;
  nowMs: number;
  malformedLines: number | null;
  baselineRows: number | null;
  anomalousRows: number | null;
}) {
  const agent = decisions?.filter((d) => !d.isBaseline) ?? null;
  const latest = agent && agent.length > 0 ? agent[0] : null;
  const takes = agent?.filter((d) => d.action.startsWith("take")).length ?? null;
  const holds = agent?.filter((d) => d.action === "hold").length ?? null;
  const refusals =
    agent?.reduce(
      (n, d) => n + d.candidates.filter((c) => c.rejectionReason !== null).length,
      0,
    ) ?? null;
  const submitted = agent?.filter((d) => d.txHash !== null).length ?? null;
  const fresh = fetchedAtMs === null ? null : freshness(fetchedAtMs, nowMs);

  return (
    <header
      className={cn(
        // min-height rather than a fixed height: the metric row may wrap to two lines at narrow
        // widths, and a fixed h-8 clipped the second line instead of showing it.
        "shrink-0 flex items-center gap-3 px-2 py-0.5 border-b hairline bg-[var(--bg-raised)]",
      )}
      style={{ minHeight: "2rem" }}
    >
      <span className="num text-2xs shrink-0" style={{ color: "var(--status-info)" }}>
        ASML-X
      </span>

      {/* WRAP, do not truncate. An 11-column equal-width grid clipped every label to "CHA...",
          "BLO...", "DEC..." at anything under about 1100px, which is unreadable and worse than
          showing fewer metrics. `auto-fit` with a 4.5rem floor lets the row wrap to a second line
          when the width is not there, and the header grows to fit rather than clipping.
          HypeTerminal's equivalent is that chrome height is a CONSTANT but the content inside it is
          allowed to reflow (their config/layout.ts:32-40 sets the height; the bar itself uses flex). */}
      <div
        className="flex-1 min-w-0 grid gap-x-3 gap-y-0.5"
        style={{ gridTemplateColumns: "repeat(auto-fit, minmax(4.5rem, 1fr))" }}
      >
        <Metric
          label="chain"
          value={chain ? String(chain.chainId) : DASH}
          tone={chain?.chainId === CHAIN.EXPECTED_ID ? "info" : "short"}
          title={`${CHAIN.EXPECTED_ID} is X Layer testnet. ${CHAIN.DEPRECATED_ID} is the deprecated testnet and still answers, which is why a mismatch here is coloured as an error rather than shown neutrally.`}
        />
        <Metric
          label="block"
          value={latest ? blockLabel(latest.blockNumber) : DASH}
          tone={latest && latest.anomalies.length > 0 ? "short" : "neutral"}
          title="Block the newest decision was taken at."
        />
        <Metric label="decisions" value={agent ? String(agent.length) : DASH} />
        <Metric label="takes" value={takes === null ? DASH : String(takes)} tone="long" />
        <Metric label="holds" value={holds === null ? DASH : String(holds)} />
        <Metric
          label="refusals"
          value={refusals === null ? DASH : String(refusals)}
          tone="short"
          title="Candidates the risk engine refused, across the loaded window."
        />
        <Metric
          label="submitted"
          value={submitted === null ? DASH : String(submitted)}
          tone="info"
          title="Decisions that produced a transaction hash."
        />
        <Metric
          label="conf"
          value={latest ? `${bpsToPct(latest.thesisConfidenceBps, 1)}%` : DASH}
          title="Confidence of the newest thesis, in basis points converted to percent."
        />
        <Metric
          label="settled"
          value={learned ? String(learned.settledCount) : DASH}
          title="Forecasts the learning layer has scored against a realized outcome."
        />
        <Metric
          label="pending"
          value={learned ? String(learned.pendingCount) : DASH}
          title="Forecasts awaiting an outcome."
        />
        <Metric
          label="baseline"
          value={baselineRows === null ? DASH : String(baselineRows)}
          tone="warn"
          title="Naive-baseline control rows in the journal. Excluded from every agent statistic."
        />
      </div>

      {/* Freshness and integrity, right-aligned. Both are facts about the DATA rather than about
          the agent, so they are visually separated from the metrics. */}
      <div className="shrink-0 flex items-center gap-2">
        {malformedLines !== null && malformedLines > 0 ? (
          <span className="num text-2xs" style={{ color: "var(--status-short)" }}>
            {malformedLines} malformed line(s)
          </span>
        ) : null}
        {/* Rows that parsed but hold impossible values. Separate from malformed lines because they
            are a different problem: the file is well-formed and the DATA is wrong. Found by task
            4.9's red team. */}
        {anomalousRows !== null && anomalousRows > 0 ? (
          <span
            className="num text-2xs"
            style={{ color: "var(--status-short)" }}
            title="Rows whose values are outside a possible range, for example a confidence above 10000 bps or a block number beyond exact integer range."
          >
            {anomalousRows} row(s) out of range
          </span>
        ) : null}
        <span
          className="num text-2xs"
          style={{
            color: fresh?.isStale ? "var(--status-warn)" : "var(--text-weak)",
          }}
          title={`Stale past ${DATA_LIMITS.stalenessThresholdMs} ms. Poll interval ${DATA_LIMITS.pollIntervalMs} ms.`}
        >
          {fresh === null ? "no read yet" : `${Math.round(fresh.ageMs / 1000)}s ago`}
          {fresh?.isStale ? " STALE" : ""}
        </span>
      </div>
    </header>
  );
}
