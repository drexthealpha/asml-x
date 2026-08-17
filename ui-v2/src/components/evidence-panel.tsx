/**
 * Evidence for the selected decision.
 *
 * Every journal row carries an `evidence` array: the exact chain reads the decision was based on,
 * e.g. "eth_call venue.orderCount and orders at block 37811602". Nothing in the v1 UI displayed
 * it, which meant the most auditable field in the record was invisible.
 *
 * Two reasons this panel exists rather than more chrome:
 * 1. It is the per-decision half of the chain-of-evidence idea. The repo-level index answers "what
 *    proves this claim"; this answers "what did the agent actually read before it decided".
 * 2. The density measurement needed real content in the bottom right, and the rule from
 *    evidence/phase4/density-measured.md is that the fill has to be data the files already carry.
 *    Decoration would have been the wrong answer to a 512x320 void.
 *
 * PATTERNS APPLIED (evidence/ui-study.md): 12px rows at py-0.5 px-2, uppercase tracked header,
 * and a distinct empty sentence in the panel body (orderbook-panel.tsx:104,151-153).
 */

import type { Decision } from "../lib/data";
import { Panel, PanelEmpty, PanelError } from "./primitives";

export function EvidencePanel({
  decision,
  error,
}: {
  decision: Decision | null;
  /** Passed so this panel NAMES its missing source under task 4.7 instead of showing a neutral
   * "waiting" sentence. The no-data proof found it was the only panel of seven that did not say
   * which file it needed, which is a smaller version of the same defect as showing a zero. */
  error?: { source: string; reason: string };
}) {
  return (
    <Panel
      className="flex-1 min-h-0"
      title="Evidence for this decision"
      meta={
        decision ? (
          <>
            <span className="num">#{decision.decisionId}</span>
            <span className="num">{decision.evidence.length} read(s)</span>
          </>
        ) : null
      }
    >
      {error ? (
        <PanelError source={error.source} reason={error.reason} />
      ) : !decision ? (
        <PanelEmpty what="a decision to be selected" />
      ) : decision.evidence.length === 0 ? (
        <div className="flex-1 min-h-0 flex items-center justify-center px-3 py-4 text-center">
          <p className="text-xs" style={{ color: "var(--status-warn)" }}>
            This decision recorded no evidence lines. A decision without its reads is not
            auditable, and that is a defect in the record rather than an empty panel.
          </p>
        </div>
      ) : (
        <div className="flex-1 min-h-0 overflow-y-auto scroll-thin">
          {decision.evidence.map((e, i) => (
            <div
              key={`${i}-${e.slice(0, 24)}`}
              className="grid grid-cols-[1.5rem_minmax(0,1fr)] gap-2 px-2 py-0.5 border-b hairline last:border-b-0"
            >
              <span className="num text-2xs text-[var(--text-weak)]">{i + 1}</span>
              <span className="text-2xs text-[var(--text-weak)] break-words" title={e}>
                {e}
              </span>
            </div>
          ))}
          <p className="px-2 py-1 text-xs text-[var(--text-weak)]">
            These are the chain reads this decision rests on, recorded by the agent at decision
            time. Block numbers here can be checked against the explorer directly.
          </p>
        </div>
      )}
    </Panel>
  );
}
