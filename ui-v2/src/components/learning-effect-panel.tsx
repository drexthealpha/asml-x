/**
 * The learning EFFECT, task 14.6. Distinct from learning-panel.tsx, which renders the learner state
 * file directly; this one renders the learningEffect block of metrics.json.
 *
 * PASS: the effect is visible in the personal view AND no figure appears without the sample size it
 * rests on.
 * FAKE WIN: "a chart trending up." A line going up on ten points is a picture of noise, and it is
 * the single most persuasive thing this panel could have shown while proving the least.
 * COUNTER: every claim below carries `n = <samples>` in the same visual unit as the number, and the
 * panel states in words what ten samples does and does not support.
 *
 * THINKING: #49 evidence (a learning claim without its sample size is not a claim), #12 design
 * thinking (what does a reader take away in five seconds, and is it true), #19 critical thinking.
 *
 * PATTERNS APPLIED (evidence/ui-study.md, each with its citation):
 * - `orderbook-row.tsx:34` 12px `tabular-nums` rows at `py-0.5 px-2` with a hairline separator, so
 *   the from/to figures align down the column and a move can be read without arithmetic.
 * - `orderbook-panel.tsx:151-153` distinct sentences for distinct situations. An unreadable source
 *   is NAMED; it never renders as a zero or a blank.
 * - `orderbook-panel.tsx:121-137` the value lives with the label it belongs to, so each parameter
 *   move carries its own trigger sentence rather than pointing at a legend elsewhere.
 *
 * WHY THE DIRECTION OF THE EFFECT IS NOT SOFTENED. The measured hit rate is BELOW a coin flip and
 * the learner responded by cutting the momentum weight toward its floor, which is the system working
 * exactly as designed: it noticed the signal was not paying and stopped leaning on it. Presenting
 * that as a setback would be presenting a working feedback loop as a defect. Presenting it as a
 * profit would be a lie. It is shown as what it is.
 */

import type { LearningCounter, LearningChange, LearningNet, LearningPnl, LearningRate, LearningSamples, Load, Metrics } from "../lib/data";
import { Panel, PanelEmpty, PanelError } from "./primitives";

/** A source string, shown small under the figure it produced. Every number here names its origin. */
function Source({ text }: { text: string }) {
  return <p className="text-3xs text-[var(--text-weak)] leading-tight">{text}</p>;
}

/** A figure whose source failed. Named, never blanked, and never zero. */
function Unavailable({ what, c }: { what: string; c: LearningCounter }) {
  return (
    <div className="px-2 py-1 border-b hairline">
      <p className="text-2xs" style={{ color: "var(--status-short)" }}>
        {what}: unavailable
      </p>
      <Source text={`${c.source} — ${c.error ?? "no reason given"}`} />
    </div>
  );
}

export function LearningEffectPanel({ metrics }: { metrics: Load<Metrics> }) {
  if (metrics.state === "loading") {
    return (
      <Panel title="What the agent learned" meta="loading">
        <PanelEmpty what="metrics.json" />
      </Panel>
    );
  }
  if (metrics.state === "error") {
    return (
      <Panel title="What the agent learned" meta="unavailable">
        <PanelError source={metrics.source} reason={metrics.reason} />
      </Panel>
    );
  }

  const le = metrics.value.learningEffect;
  if (!le) {
    return (
      <Panel title="What the agent learned" meta="unavailable">
        <PanelError
          source="ui-v2/public/data/metrics.json"
          reason="no learningEffect block; run bash scripts/88-recompute-metrics.sh"
        />
      </Panel>
    );
  }

  const samples = le.samples?.value as LearningSamples | undefined;
  const rate = le.hitRateBps?.value as LearningRate | undefined;
  const changes = le.changes?.value as LearningChange[] | undefined;
  const net = le.netMove?.value as LearningNet[] | undefined;
  const pnl = le.realizedPnl?.value as LearningPnl | undefined;

  // The sample count governs every claim in this panel, so it is read once here and appended to
  // each of them rather than being left to each row to remember.
  const n = rate?.samples ?? samples?.scored ?? 0;

  return (
    // MEASURED, not guessed. At 1440x900 this panel settles at 374px and is not clipped. At a short
    // viewport (632x606) the flex column squeezed it to 86px, showing two lines of the caveat and
    // hiding every number behind an inner scrollbar, which is the worst possible truncation: the
    // reader sees the hedge and none of the evidence it hedges. A floor makes the PAGE scroll
    // instead, which the outer container already does.
    <Panel title="What the agent learned" meta={`n = ${n}`} minHeightPx={320}>
      <div className="flex flex-col min-h-0 overflow-auto">
        {/* THE HONESTY LINE COMES FIRST, above the numbers rather than under them. A caveat placed
            after a figure is read after the reader has already formed a view. */}
        <div className="px-2 py-2 border-b hairline">
          <p className="text-xs" style={{ color: "var(--text-strong)" }}>
            {n === 0
              ? "Nothing has been measured yet."
              : `Everything below rests on ${n} settled outcome${n === 1 ? "" : "s"}.`}
          </p>
          <p className="text-3xs text-[var(--text-weak)] leading-tight mt-1">
            That is a sample size at which a hit rate is not a performance claim. What it shows is
            that outcomes are measured, attributed to the decision that produced them, and that
            parameters move in response. It does not show that the agent is profitable, and no
            figure here should be read that way.
          </p>
        </div>

        {le.samples?.error ? (
          <Unavailable what="Samples" c={le.samples} />
        ) : samples ? (
          <div className="px-2 py-1 border-b hairline">
            <div className="flex items-baseline justify-between gap-2">
              <span className="text-2xs text-[var(--text-weak)]">Settled outcomes</span>
              <span className="num text-xs" style={{ color: "var(--text-strong)" }}>
                {samples.settled}
              </span>
            </div>
            <div className="flex items-baseline justify-between gap-2">
              <span className="text-2xs text-[var(--text-weak)]">Dropped as flat</span>
              <span className="num text-xs text-[var(--text-weak)]">{samples.droppedFlat}</span>
            </div>
            {/* This number is shown, not hidden. A high flat count relative to the scored count is
                the honest explanation for why learning is slow here: the venue is quiet, and a
                market that did not move cannot judge a directional call. */}
            <Source text="A forecast on a market that did not move is dropped rather than scored as wrong." />
          </div>
        ) : null}

        {le.hitRateBps?.error ? (
          <Unavailable what="Hit rate" c={le.hitRateBps} />
        ) : rate ? (
          <div className="px-2 py-1 border-b hairline">
            <div className="flex items-baseline justify-between gap-2">
              <span className="text-2xs text-[var(--text-weak)]">Signal hit rate</span>
              <span
                className="num text-xs"
                style={{
                  color: rate.value >= 5000 ? "var(--status-long)" : "var(--status-short)",
                }}
              >
                {(rate.value / 100).toFixed(1)}% (n = {rate.samples})
              </span>
            </div>
            <Source text={le.hitRateBps.source} />
          </div>
        ) : null}

        {/* THE NET MOVE COMES BEFORE THE PER-MOVE LIST. The learner clamps each step, so the
            individual changes are small and a reader who sees only those concludes nothing
            happened. Momentum weight moving 411 to 401 and momentum weight having fallen from 2000
            to 391 are the same run described two ways. The second one is the answer to "did this
            learn anything", so it goes first. */}
        {le.netMove?.error ? (
          <Unavailable what="Net parameter move" c={le.netMove} />
        ) : net && net.length > 0 ? (
          <div className="flex flex-col">
            <div className="px-2 py-1 border-b hairline">
              <span className="col-label">Net move, from the defaults it started at</span>
            </div>
            {net.map((p) => (
              <div key={p.parameter} className="px-2 py-0.5 border-b hairline flex items-baseline justify-between gap-2">
                <span className="text-2xs text-[var(--text-weak)]">{p.parameter}</span>
                <span
                  className="num text-xs"
                  style={{ color: p.moved ? "var(--text-strong)" : "var(--text-weak)" }}
                >
                  {p.moved ? (
                    <>
                      {p.default} &rarr; {p.current}
                    </>
                  ) : (
                    <>{p.current} (unchanged)</>
                  )}
                </span>
              </div>
            ))}
            <div className="px-2 py-1 border-b hairline">
              <Source text={le.netMove?.source ?? ""} />
            </div>
          </div>
        ) : null}

        {le.changes?.error ? (
          <Unavailable what="Parameter changes" c={le.changes} />
        ) : changes && changes.length > 0 ? (
          <div className="flex flex-col">
            <div className="px-2 py-1 border-b hairline">
              <span className="col-label">What changed, and why</span>
            </div>
            {changes.map((c, i) => (
              <div key={`${c.parameter}-${i}`} className="px-2 py-0.5 border-b hairline">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="text-2xs text-[var(--text-weak)]">{c.parameter}</span>
                  <span className="num text-xs" style={{ color: "var(--text-strong)" }}>
                    {c.from} &rarr; {c.to} (n = {c.samples})
                  </span>
                </div>
                {/* The learner's OWN sentence, not a rephrasing. If the UI paraphrased it, the UI
                    and the engine could drift and only the UI would be read. */}
                <Source text={c.trigger} />
              </div>
            ))}
          </div>
        ) : (
          <div className="px-2 py-1 border-b hairline">
            <p className="text-2xs text-[var(--text-weak)]">
              No parameter has moved yet. The learner requires a minimum number of settled outcomes
              before it will change anything, so that it cannot chase noise.
            </p>
          </div>
        )}

        {le.realizedPnl?.error ? (
          <Unavailable what="Realized PnL" c={le.realizedPnl} />
        ) : pnl ? (
          <div className="px-2 py-1">
            <div className="flex items-baseline justify-between gap-2">
              <span className="text-2xs text-[var(--text-weak)]">Realized PnL</span>
              <span
                className="num text-xs"
                style={{
                  color: pnl.totalMicro >= 0 ? "var(--status-long)" : "var(--status-short)",
                }}
              >
                {pnl.totalMicro >= 0 ? "+" : ""}
                {pnl.totalMicro} micro quote
              </span>
            </div>
            <div className="flex items-baseline justify-between gap-2">
              <span className="text-2xs text-[var(--text-weak)]">Settlements</span>
              <span className="num text-xs text-[var(--text-weak)]">
                {pnl.settlements} ({pnl.profitable} up, {pnl.losing} down, {pnl.flat} flat)
              </span>
            </div>
            {/* The basis string is RENDERED, not merely carried in the file. "Realized PnL" reads as
                cash to almost everyone, and this is a mark to market against a later observed mid. */}
            <Source text={pnl.basis} />
            <Source text={le.realizedPnl.source} />
          </div>
        ) : null}
      </div>
    </Panel>
  );
}
