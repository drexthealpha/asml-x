/**
 * The growth loop, task 13.3.
 *
 * PASS: a reader reaches the loop from the landing page in under two minutes, timed.
 * FAKE WIN: "a diagram with no live numbers in it."
 * COUNTER: "each stage of the loop must show its current measured value."
 *
 * So every stage below carries a NUMBER read from `metrics.json`'s `growth` block, and that block
 * gives each counter its own `source` string. A stage whose source could not be read renders the
 * word "unavailable" rather than a zero, because zero means "this happened none times" and that is
 * a different claim from "nobody could read it".
 *
 * THINKING: #53 phenomenological (what does a reader actually take away in two minutes),
 * #12 design thinking, #19 critical thinking.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - `orderbook-row.tsx:34` 12px `tabular-nums` at `py-0.5 px-2` with hairline separators, so the
 *   numbers down the loop align and can be compared at a glance.
 * - `orderbook-panel.tsx:151-153` distinct sentences for distinct situations; an unreadable source
 *   is named, never blanked.
 * - `orderbook-panel.tsx:121-137` controls and values live with the label they belong to, so each
 *   arrow of the loop carries its own measurement rather than pointing at a legend.
 *
 * THE LOOP IS DRAWN WITH TEXT AND BORDERS, not an image. A diagram asset cannot show a live number,
 * and a diagram that has to be regenerated when a counter moves will stop matching the counter.
 */

import type { GrowthCounter, Load, Metrics } from "../lib/data";
import { Panel, PanelEmpty, PanelError } from "./primitives";

/** A stage of the loop: what happens, which counter measures it, and how to phrase it. */
const STAGES: { key: string; stage: string; because: string }[] = [
  {
    key: "coordinationCalls",
    stage: "More callers ask",
    because: "external agents request quotes from the coordination API",
  },
  {
    key: "agentActions",
    stage: "More actions execute",
    because: "each accepted decision becomes an onchain transaction",
  },
  {
    key: "feeEvents",
    stage: "More fee events fire",
    because: "every execution charges the usage fee, which cannot be skipped",
  },
  {
    key: "candidatesEvaluated",
    stage: "More decisions are recorded",
    because: "each cycle scores a full candidate set, not just the winner",
  },
  {
    key: "learningUpdates",
    stage: "More forecasts settle",
    because: "settled outcomes are what the learning layer can actually learn from",
  },
];

function fmt(v: GrowthCounter | undefined): { text: string; ok: boolean } {
  if (!v || v.error !== undefined || v.value === undefined) {
    return { text: "unavailable", ok: false };
  }
  if (typeof v.value === "object") return { text: `${Object.keys(v.value).length}`, ok: true };
  return { text: v.value.toLocaleString(), ok: true };
}

export function GrowthPanel({ metrics }: { metrics: Load<Metrics> }) {
  if (metrics.state === "loading") {
    return (
      <Panel title="The growth loop" meta="live numbers">
        <PanelEmpty what="metrics.json" />
      </Panel>
    );
  }
  if (metrics.state === "error") {
    return (
      <Panel title="The growth loop" meta="live numbers">
        <PanelError source={metrics.source} reason={metrics.reason} />
      </Panel>
    );
  }

  // A typed field, not an `unknown` cast. The cast is what let the panel compile while the mapper
  // silently dropped this block, so the panel rendered "absent from the metrics file" and the error
  // was correct for the wrong reason.
  const growth = metrics.value.growth;
  if (!growth) {
    return (
      <Panel title="The growth loop" meta="live numbers">
        <PanelError source="metrics.json growth block" reason="absent from the metrics file" />
      </Panel>
    );
  }

  const fees = growth.feesCollectedWei;
  const feeText =
    fees && fees.error === undefined && typeof fees.value === "number"
      ? `${(fees.value / 1e18).toFixed(6)} tQUOTE`
      : fees && fees.error === undefined && fees.value !== undefined
        ? `${(Number(fees.value) / 1e18).toFixed(6)} tQUOTE`
        : "unavailable";

  return (
    <Panel title="The growth loop" meta="every stage carries its live number">
      <div className="flex-1 min-h-0 overflow-y-auto">
        <p className="px-2 py-1.5 text-xs text-[var(--text-weak)]">
          Each stage feeds the next. The number beside every stage is measured now, from the source
          named under it, not drawn into a picture.
        </p>

        {STAGES.map((s, i) => {
          const c = growth[s.key];
          const { text, ok } = fmt(c);
          return (
            <div key={s.key} className="border-b hairline last:border-b-0">
              <div className="grid grid-cols-[auto_minmax(0,1fr)_auto] gap-2 px-2 py-0.5 items-baseline">
                <span className="num text-3xs text-[var(--text-weak)]">{i + 1}</span>
                <span className="text-2xs" style={{ color: "var(--text-strong)" }}>
                  {s.stage}
                </span>
                <span
                  className="num text-2xs"
                  data-testid={`growth-${s.key}`}
                  style={{ color: ok ? "var(--status-long)" : "var(--status-short)" }}
                >
                  {text}
                </span>
              </div>
              <p className="px-2 pb-1 pl-6 text-3xs text-[var(--text-weak)]">
                {s.because}
                {c ? ` — source: ${c.source}` : null}
              </p>
            </div>
          );
        })}

        <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-1 border-b hairline bg-[var(--fill-hover)]">
          <span className="text-2xs" style={{ color: "var(--text-strong)" }}>
            Revenue collected so far
          </span>
          <span className="num text-2xs" data-testid="growth-fees" style={{ color: "var(--status-long)" }}>
            {feeText}
          </span>
        </div>

        <p className="px-2 py-2 text-3xs text-[var(--text-weak)]">
          The loop closes because better decisions come from more settled outcomes, and more settled
          outcomes come from more usage. This is a small system: the numbers above are what it has
          actually done, and no scale is claimed beyond them.
        </p>
      </div>
    </Panel>
  );
}
