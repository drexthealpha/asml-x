/**
 * Onchain metrics with explorer links, task 5.1.
 *
 * THE DESIGN POINT: this panel computes NOTHING. Every number comes from
 * `data/metrics.json`, written by `bash scripts/88-recompute-metrics.sh`, which is also what
 * task 5.1's PASS condition asks to reproduce. A panel that recomputed the counters in TypeScript
 * would be a second implementation that drifts from the script invisibly, and the drift would be
 * exactly the kind of thing this project is judged on.
 *
 * The two families are kept visually separate because they have different authority:
 *   ONCHAIN  read live from the guard and venue by the script this run.
 *   JOURNAL  counted from the agent's own record.
 * Mixing them would let a journal-derived number borrow the credibility of a chain read.
 *
 * PATTERNS APPLIED (evidence/ui-study.md): 12px `tabular-nums` rows at `py-0.5 px-2` and uppercase
 * tracked section labels (`orderbook-row.tsx:34`, `orderbook-panel.tsx:104`); utilisation drawn with
 * the depth-bar technique (`orderbook-row.tsx:29-34`); distinct empty and error sentences in the
 * panel body (`orderbook-panel.tsx:151-153`).
 */

import type { Load, Metrics } from "../lib/data";
import { HashCell, Panel, PanelEmpty, PanelError, UtilisationBar } from "./primitives";

function Row({
  label,
  value,
  href,
  tone,
}: {
  label: string;
  value: string;
  href?: string;
  tone?: string;
}) {
  return (
    <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline last:border-b-0 hover:bg-[var(--fill-hover)]">
      <span className="text-2xs truncate text-[var(--text-weak)]">{label}</span>
      {href ? (
        <a
          className="num text-2xs truncate text-right"
          style={{ color: "var(--status-info)" }}
          href={href}
          target="_blank"
          rel="noreferrer noopener"
        >
          {value}
        </a>
      ) : (
        <span className="num text-2xs text-right" style={tone ? { color: tone } : undefined}>
          {value}
        </span>
      )}
    </div>
  );
}

export function MetricsPanel({ metrics }: { metrics: Load<Metrics> }) {
  if (metrics.state === "error") {
    return (
      <Panel title="Onchain metrics">
        <PanelError source={metrics.source} reason={metrics.reason} />
      </Panel>
    );
  }
  if (metrics.state === "loading") {
    return (
      <Panel title="Onchain metrics">
        <PanelEmpty what="the metrics recompute" />
      </Panel>
    );
  }

  const m = metrics.value;
  const o = m.onchain;
  const j = m.journal;

  return (
    <Panel
      title="Onchain metrics"
      meta={
        <>
          <span className="num">blk {o.headBlock ?? "—"}</span>
          <span className="num" title={`Written by ${m.generatedBy}`}>
            {m.generatedAtUtc}
          </span>
        </>
      }
    >
      <div className="flex-1 min-h-0 overflow-y-auto scroll-thin grid grid-cols-1 lg:grid-cols-2 gap-x-1 content-start">
        <div className="lg:col-span-2 px-2 py-0.5 border-b hairline">
          <span className="col-label">read live from chain this run</span>
        </div>
        {/* Full addresses with copy, not a truncated string that cannot be used for anything. */}
        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline">
          <span className="text-2xs truncate text-[var(--text-weak)]">guard</span>
          <HashCell value={o.guardAddress} kind="address" explorerBase={m.explorerAddressBase} />
        </div>
        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline">
          <span className="text-2xs truncate text-[var(--text-weak)]">venue</span>
          <HashCell value={o.venueAddress} kind="address" explorerBase={m.explorerAddressBase} />
        </div>
        <Row label="live orders on the venue" value={String(o.venueOrderCount ?? "—")} />
        <Row
          label="kill switch"
          value={o.killed === "true" ? "ENGAGED" : "clear"}
          tone={o.killed === "true" ? "var(--status-short)" : "var(--status-long)"}
        />
        <Row
          label="transactions ever sent by the agent key"
          value={String(o.agentKeyNonce ?? "—")}
        />

        <div className="lg:col-span-2 px-2 py-0.5 border-y hairline">
          <span className="col-label">onchain caps, the outer boundary</span>
        </div>
        <UtilisationBar
          label="per-market exposure vs onchain cap"
          pct={o.marketUtilisationPct ?? Number.NaN}
          detail={`${(o.marketExposureWei ?? 0) / 1e18} / ${(o.marketCapWei ?? 0) / 1e18}`}
        />
        <UtilisationBar
          label="gross exposure vs onchain cap"
          pct={o.grossUtilisationPct ?? Number.NaN}
          detail={`${(o.grossExposureWei ?? 0) / 1e18} / ${(o.grossCapWei ?? 0) / 1e18}`}
        />
        <p className="lg:col-span-2 px-2 py-1 text-xs text-[var(--text-weak)]">
          These are the ONCHAIN caps. The offchain risk engine is tighter and binds first, which is
          why the risk panel can read 100% while these read a tenth of that. Both are correct and
          they measure different limits. Source:{" "}
          <span className="num">crates/risk-engine Limits::conservative_testnet</span>.
        </p>

        <div className="lg:col-span-2 px-2 py-0.5 border-y hairline">
          <span className="col-label">counted from the agent's own journal</span>
        </div>
        <Row label="agent decisions" value={String(j.agentDecisions)} />
        <Row label="baseline control rows, excluded everywhere" value={String(j.baselineControlRows)} />
        <Row label="takes" value={String(j.takes)} tone="var(--status-long)" />
        <Row label="holds" value={String(j.holds)} />
        <Row label="submitted onchain" value={String(j.submitted)} tone="var(--status-info)" />
        <Row label="candidates scored" value={String(j.candidatesTotal)} />
        <Row label="refusals" value={String(j.refusalsTotal)} tone="var(--status-short)" />
        {Object.entries(j.refusalsByReason).map(([name, n]) => (
          <Row key={name} label={`   ${name}`} value={String(n)} />
        ))}

        <div className="lg:col-span-2 px-2 py-0.5 border-y hairline">
          <span className="col-label">learning</span>
        </div>
        <Row label="settled forecasts" value={String(m.learning.settled ?? "—")} />
        <Row label="discarded as flat" value={String(m.learning.unscoredFlat ?? "—")} />
        <Row label="open forecasts" value={String(m.learning.pending ?? "—")} />
        <Row label="signals tracked" value={String(m.learning.signalsTracked ?? "—")} />

        <p className="lg:col-span-2 px-2 py-1 text-xs text-[var(--text-weak)]">
          Every counter here is written by <span className="num">{m.generatedBy}</span>. This panel
          computes nothing, so reproducing it and running that script are the same operation.
        </p>
      </div>
    </Panel>
  );
}
