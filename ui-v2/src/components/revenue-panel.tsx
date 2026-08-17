/**
 * Live fee revenue, task 7.7.
 *
 * THE POINT OF THIS FILE IS WHAT IT DOES NOT DO. TASKS.md names this phase's headline fake win as
 * "a counter incremented in TypeScript on each decision". So there is no arithmetic on fees anywhere
 * in this component: no sum, no multiply, no divide, no accumulator, no `+= fee`. Every figure is a
 * string that came from `data/metrics.json`, which `bash scripts/88-recompute-metrics.sh` wrote from
 * `FeeCollector.chargeCount()`, `totalCollected()` and decoded `FeeCharged` logs. A grep in
 * scripts/107-fee-ui-gate.sh asserts that absence rather than trusting this comment.
 *
 * The wei-to-token rendering below is the one transformation performed, and it is a FORMAT, not a
 * computation: it inserts a decimal point into a digit string and never converts to Number. A
 * 0.1e18 fee is 100000000000000000, which is inside float range, but a total that grows past 2^53
 * would silently lose precision, and a revenue figure that quietly rounds is the same defect as a
 * revenue figure that is invented. String slicing has no such ceiling.
 *
 * FAILURE IS VISIBLE. If the fee chain read failed, `metrics.fees` carries an `error` and NO totals,
 * and this renders PanelError. It must never show a zero, because a zero says the business earned
 * nothing and a failed read says nothing at all, and those are different facts.
 *
 * PATTERNS APPLIED (evidence/ui-study.md): 12px `tabular-nums` rows at `py-0.5 px-2` with a hairline
 * separator and uppercase tracked section labels (`orderbook-row.tsx:34`, `orderbook-panel.tsx:104`);
 * hash cells linking out to the explorer (`trades-panel.tsx:61`); distinct empty and error sentences
 * in the panel body rather than a shared blank (`orderbook-panel.tsx:151-153`).
 */

import type { Load, Metrics } from "../lib/data";
import { HashCell, Panel, PanelEmpty, PanelError } from "./primitives";

/**
 * Insert a decimal point into a wei digit string. Pure string manipulation: no Number, no BigInt
 * arithmetic, no rounding of a value that matters. `dp` digits are shown after the point.
 */
function formatWei(wei: string, dp = 4): string {
  if (!/^\d+$/.test(wei)) return "n/a";
  const padded = wei.padStart(19, "0");
  const whole = padded.slice(0, padded.length - 18).replace(/^0+(?=\d)/, "");
  const frac = padded.slice(padded.length - 18, padded.length - 18 + dp);
  return `${whole}.${frac}`;
}

function Row({ label, value, tone }: { label: string; value: string; tone?: string }) {
  return (
    <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline last:border-b-0 hover:bg-[var(--fill-hover)]">
      <span className="text-2xs truncate text-[var(--text-weak)]">{label}</span>
      <span className="num text-2xs text-right" style={tone ? { color: tone } : undefined}>
        {value}
      </span>
    </div>
  );
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div className="px-2 py-1 text-3xs uppercase tracking-wider text-[var(--text-weak)] border-b hairline">
      {children}
    </div>
  );
}

export function RevenuePanel({ metrics }: { metrics: Load<Metrics> }) {
  if (metrics.state === "loading") {
    return (
      <Panel title="Revenue" meta="usage fee">
        <PanelEmpty what="metrics.json" />
      </Panel>
    );
  }
  if (metrics.state === "error") {
    return (
      <Panel title="Revenue" meta="usage fee">
        <PanelError source={metrics.source} reason={metrics.reason} />
      </Panel>
    );
  }

  const fees = metrics.value.fees;

  // The whole reason `fees` is allowed to be absent. A failed chain read renders as an error, never
  // as zero revenue.
  if (!fees || fees.error || fees.totalFeesWei === undefined) {
    return (
      <Panel title="Revenue" meta="usage fee">
        <PanelError
          source="FeeCollector, read via scripts/fee_logs.py"
          reason={fees?.error ?? "no fee data in metrics.json"}
        />
      </Panel>
    );
  }

  const addrBase = metrics.value.explorerAddressBase;
  const txBase = metrics.value.explorerTxBase;

  return (
    <Panel title="Revenue" meta={`${fees.feeBps} bps usage fee`}>
      <div className="flex-1 min-h-0 overflow-y-auto">
        <SectionLabel>Collected, from contract state</SectionLabel>
        <Row label="Total fees" value={`${formatWei(fees.totalFeesWei)} tQUOTE`} tone="var(--status-long)" />
        <Row label="Fees charged" value={String(fees.eventCount)} />
        <Row label="Rate" value={`${fees.feeBps} bps`} />

        <SectionLabel>Contracts</SectionLabel>
        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline">
          <span className="text-2xs truncate text-[var(--text-weak)]">Collector</span>
          <HashCell value={fees.collector} kind="address" explorerBase={addrBase} />
        </div>
        {fees.treasury ? (
          <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline">
            <span className="text-2xs truncate text-[var(--text-weak)]">Treasury</span>
            <HashCell value={fees.treasury} kind="address" explorerBase={addrBase} />
          </div>
        ) : null}

        <SectionLabel>
          Recent charges{fees.recentIsComplete === false ? " (partial scan)" : ""}
        </SectionLabel>
        {fees.recent && fees.recent.length > 0 ? (
          fees.recent.map((e) => (
            <div
              key={`${e.tx}-${e.logIndex}`}
              className="grid grid-cols-[auto_minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline last:border-b-0 hover:bg-[var(--fill-hover)]"
            >
              <span className="num text-2xs text-[var(--text-weak)]">{e.block}</span>
              <HashCell value={e.tx} kind="tx" explorerBase={txBase} />
              <span className="num text-2xs text-right" style={{ color: "var(--status-long)" }}>
                {formatWei(e.feeWei)}
              </span>
            </div>
          ))
        ) : (
          <PanelEmpty what="a FeeCharged event on chain" />
        )}

        <p className="px-2 py-2 text-3xs text-[var(--text-weak)]">
          Totals read from FeeCollector state. Rows decoded from FeeCharged logs. This panel performs
          no arithmetic on fees.
        </p>
      </div>
    </Panel>
  );
}
