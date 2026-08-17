/**
 * The learning panel, task 5.6. Renders `learned-state.json`: what the learner has settled, what it
 * is still waiting on, and which parameters have moved from their documented defaults.
 *
 * RECONSTRUCTED 2026-08-16. The previous version of this file was overwritten in error while adding
 * task 14.6's panel, and it was untracked, so no copy existed in git or in any session transcript.
 * This is a rebuild against the same props `App.tsx` passes and the same types in `lib/data.ts`, not
 * a recovery. It is recorded here rather than passed off as the original, because a file that was
 * silently rewritten is exactly the kind of thing an audit should be able to find.
 *
 * Task 14.6's learning EFFECT panel is a different component in `learning-effect-panel.tsx`. Two
 * panels, two files: this one reads the learner's state file directly, that one reads the
 * `learningEffect` block of `metrics.json` and pairs every figure with its sample size.
 *
 * PATTERNS APPLIED (evidence/ui-study.md, each with its citation):
 * - `orderbook-row.tsx:34` 12px `tabular-nums` rows at `py-0.5 px-2` with hairline separators, so
 *   the from/to figures and the per-signal tallies align down their columns.
 * - `orderbook-panel.tsx:151-153` distinct sentences for distinct situations. An unreadable source
 *   is named; a state with nothing settled says so in words rather than rendering zeros.
 * - `orderbook-panel.tsx:121-137` each value sits with the label it belongs to.
 *
 * WHY THE DEFAULTS ARE SHOWN BESIDE THE CURRENT VALUES. Task 5.6 asks for "after N settled outcomes
 * I changed X from A to B". The state file records only the current value, so the baseline comes
 * from `LEARNED_DEFAULTS` in `lib/data.ts`, which cites the crate it was copied from. Without it a
 * reader sees a number and cannot tell whether anything has been learned at all.
 */

import type { Decision, LearnedState } from "../lib/data";
import { Panel, PanelEmpty, PanelError } from "./primitives";

export function LearningPanel({
  learned,
  decisions,
  error,
}: {
  learned: LearnedState | null;
  decisions: Decision[];
  error?: { source: string; reason: string };
}) {
  if (error) {
    return (
      <Panel title="Learning" meta="unavailable">
        <PanelError source={error.source} reason={error.reason} />
      </Panel>
    );
  }
  if (!learned) {
    return (
      <Panel title="Learning" meta="loading">
        <PanelEmpty what="learned-state.json" />
      </Panel>
    );
  }

  // Agent decisions only. The naive-baseline control rows are not decisions the agent made, and
  // mixing them into an agent statistic is the error that once inflated the river benchmark's
  // margin from 2.5 points to 11.5.
  const agentDecisions = decisions.filter((d) => !d.isBaseline).length;
  const moved = learned.params.filter((p) => p.currentBps !== p.defaultBps);

  return (
    <Panel
      title="Learning"
      meta={`${learned.settledCount} settled / ${learned.pendingCount} pending`}
    >
      <div className="flex flex-col min-h-0 overflow-auto">
        <div className="px-2 py-1 border-b hairline flex items-baseline justify-between gap-2">
          <span className="text-2xs text-[var(--text-weak)]">Agent decisions</span>
          <span className="num text-xs" style={{ color: "var(--text-strong)" }}>
            {agentDecisions}
          </span>
        </div>
        <div className="px-2 py-1 border-b hairline flex items-baseline justify-between gap-2">
          <span className="text-2xs text-[var(--text-weak)]">Settled outcomes</span>
          <span className="num text-xs" style={{ color: "var(--text-strong)" }}>
            {learned.settledCount}
          </span>
        </div>
        <div className="px-2 py-1 border-b hairline">
          <div className="flex items-baseline justify-between gap-2">
            <span className="text-2xs text-[var(--text-weak)]">Dropped as flat</span>
            <span className="num text-xs text-[var(--text-weak)]">{learned.unscoredFlat}</span>
          </div>
          {/* Shown rather than buried. A high flat count relative to settled outcomes means the
              venue is too quiet to learn from, which is information about the market and not a
              defect in the learner. */}
          <p className="text-3xs text-[var(--text-weak)] leading-tight">
            A forecast on a market that did not move is dropped, not scored as wrong.
          </p>
        </div>

        {/* Per-signal accuracy. Every rate carries its sample count in the same row: a hit rate
            without its n is not a claim anyone can check. */}
        <div className="px-2 py-1 border-b hairline">
          <span className="col-label">Signals</span>
        </div>
        {learned.stats.length === 0 ? (
          <div className="px-2 py-1 border-b hairline">
            <p className="text-2xs text-[var(--text-weak)]">
              No signal has a scored sample yet, so no hit rate exists. This is not a hit rate of
              zero, which would be a claim that the signal is always wrong.
            </p>
          </div>
        ) : (
          learned.stats.map((s) => (
            <div key={s.name} className="px-2 py-0.5 border-b hairline">
              <div className="flex items-baseline justify-between gap-2">
                <span className="text-2xs text-[var(--text-weak)]">{s.name}</span>
                <span
                  className="num text-xs"
                  style={{
                    color: s.hitRateBps >= 5000 ? "var(--status-long)" : "var(--status-short)",
                  }}
                >
                  {(s.hitRateBps / 100).toFixed(1)}% ({s.correct}/{s.samples})
                </span>
              </div>
              <p className="text-3xs text-[var(--text-weak)] leading-tight">
                mean edge error{" "}
                {s.samples > 0 ? Math.round(s.sumEdgeErrorMicro / s.samples) : 0} micro over{" "}
                {s.samples} outcome{s.samples === 1 ? "" : "s"}
              </p>
            </div>
          ))
        )}

        {/* Parameters, current against the documented default, so a change reads as a change. */}
        <div className="px-2 py-1 border-b hairline">
          <span className="col-label">
            Parameters {moved.length > 0 ? `(${moved.length} moved)` : "(none moved yet)"}
          </span>
        </div>
        {learned.params.map((p) => {
          const changed = p.currentBps !== p.defaultBps;
          return (
            <div key={p.name} className="px-2 py-0.5 border-b hairline flex items-baseline justify-between gap-2">
              <span className="text-2xs text-[var(--text-weak)]">{p.name}</span>
              <span
                className="num text-xs"
                style={{ color: changed ? "var(--text-strong)" : "var(--text-weak)" }}
              >
                {changed ? (
                  <>
                    {p.defaultBps} &rarr; {p.currentBps}
                  </>
                ) : (
                  <>{p.currentBps} (unchanged)</>
                )}
              </span>
            </div>
          );
        })}
        {moved.length > 0 ? (
          <div className="px-2 py-1 border-b hairline">
            <p className="text-3xs text-[var(--text-weak)] leading-tight">
              Baselines are `Params::default()` in crates/decision-engine/src/lib.rs. The state file records
              only the current value, so the starting point has to come from the crate.
            </p>
          </div>
        ) : null}

        {/* Open forecasts, shown as rows rather than as a count alone. */}
        <div className="px-2 py-1 border-b hairline">
          <span className="col-label">Open forecasts ({learned.pendingCount})</span>
        </div>
        {learned.pending.length === 0 ? (
          <div className="px-2 py-1">
            <p className="text-2xs text-[var(--text-weak)]">
              Nothing outstanding. Every forecast made so far has settled or been dropped as flat.
            </p>
          </div>
        ) : (
          learned.pending.map((p, i) => (
            <div
              key={`${p.signalName}-${p.openedAtMs}-${i}`}
              className="px-2 py-0.5 border-b hairline flex items-baseline justify-between gap-2"
            >
              <span className="text-2xs text-[var(--text-weak)]">
                {p.signalName} predicts {p.predicted}
              </span>
              <span className="num text-xs text-[var(--text-weak)]">
                mid {p.midAtDecisionMicro}, edge {p.expectedEdgeMicro}
              </span>
            </div>
          ))
        )}
      </div>
    </Panel>
  );
}
