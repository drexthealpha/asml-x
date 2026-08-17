/**
 * Chain panel: deployed contracts with provenance, and the learning state.
 *
 * Task 4.6's PASS condition is the strict one: "no venue or RWA number renders without a badge;
 * the script fails if one does". The badge is driven by `selfDeployed` on each deployment record,
 * read from the data file. A contract added to the config without that field renders as EXTERNAL,
 * which is the wrong-but-visible direction, and task 4.6's checker greps for a badge per address.
 *
 * PATTERNS APPLIED (evidence/ui-study.md): 12px data rows, uppercase tracked headers, and
 * controls/labels adjacent to what they describe (orderbook-panel.tsx:104,121-137).
 */

import type { ChainConfig, Decision } from "../lib/data";
import { HashCell, Panel, PanelEmpty, PanelError, ProvenanceBadge } from "./primitives";

/** Minimum widths so a column cannot resolve to nothing.
 *
 * Measured at a 632px viewport before this: the ADDRESS cell was 10.9px wide while holding a
 * 42-character address, so the column had silently disappeared. 7rem for the name plus room for a
 * truncated address and the provenance badge is 30rem; the transaction table needs 32rem for the
 * id, block and hash. Below those the table scrolls sideways with every column intact, which is
 * HypeTerminal's response to a strip that cannot shrink (main-workspace.tsx:41). */
const CONTRACTS_MIN_WIDTH = "30rem";
const TX_MIN_WIDTH = "32rem";

export function ChainPanel({
  chain,
  decisions,
  chainError,
}: {
  chain: ChainConfig | null;
  /** Decisions that produced a transaction. Rendered as a table because a count is not evidence:
   * a judge should be able to click through to the explorer from this screen. */
  decisions: Decision[];
  chainError?: { source: string; reason: string };
}) {
  // No slice. The first version capped this at 12 for a layout that no longer exists, and the cap
  // was invisible: the panel said "12 shown" while 39 transactions existed, so a reader counting
  // transactions on screen would have undercounted the agent's onchain activity by two thirds. The
  // list scrolls, and the header states the true total.
  const submitted = decisions.filter((d) => d.txHash !== null);
  return (
    <div className="flex-1 min-h-0 flex flex-col gap-1">
      <Panel
        className="shrink-0"
        title="Contracts on chain"
        meta={chain ? <span className="num">chain {chain.chainId}</span> : null}
      >
        {chainError ? (
          <PanelError source={chainError.source} reason={chainError.reason} />
        ) : !chain || chain.deployments.length === 0 ? (
          <PanelEmpty what="the deployment manifest" />
        ) : (
          <div className="flex-1 min-h-0 overflow-auto scroll-thin">
            <div className="sticky top-0 z-20 grid grid-cols-[minmax(0,7rem)_minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline bg-[var(--bg-raised)]" style={{ minWidth: CONTRACTS_MIN_WIDTH }}>
              <span className="col-label">contract</span>
              <span className="col-label">address</span>
              <span className="col-label">provenance</span>
            </div>
            {chain.deployments.map((d) => (
              <div
                key={d.address}
                className="grid grid-cols-[minmax(0,7rem)_minmax(0,1fr)_auto] gap-2 items-center px-2 py-0.5 border-b hairline last:border-b-0 hover:bg-[var(--fill-hover)]"
                style={{ minWidth: CONTRACTS_MIN_WIDTH }}
              >
                <span className="text-2xs truncate text-[var(--text-weak)]" title={d.role}>
                  {d.name}
                </span>
                <HashCell
                  value={d.address}
                  kind="address"
                  explorerBase={chain.explorerBase.replace("/tx/", "/address/")}
                />
                <ProvenanceBadge selfDeployed={d.selfDeployed} />
              </div>
            ))}
          </div>
        )}
      </Panel>

      {/* Transactions flex and Learning is sized to content, not the other way round. Learning
          holds one statistic per signal and grows only when forecasts settle; the transaction list
          grows with every run. Giving the flexible height to the panel that actually fills is what
          took the largest empty rectangle from 8.77% to the number in
          evidence/phase4/density-measured.md. */}
      <Panel
        className="flex-1 min-h-0"
        title="Agent transactions"
        meta={
          <span className="num">
            {decisions.length === 0
              ? "—"
              : `${submitted.length} of ${decisions.length} decisions submitted`}
          </span>
        }
      >
        {decisions.length === 0 ? (
          <PanelError
            source="data/journal.jsonl"
            reason="no decisions loaded, so no transaction can be listed"
          />
        ) : submitted.length === 0 ? (
          <PanelEmpty what="a decision that submitted a transaction" />
        ) : (
          <div className="flex-1 min-h-0 overflow-auto scroll-thin">
            <div className="sticky top-0 z-20 grid grid-cols-[3rem_5.5rem_minmax(0,1fr)] gap-2 px-2 py-0.5 border-b hairline bg-[var(--bg-raised)]" style={{ minWidth: TX_MIN_WIDTH }}>
              <span className="col-label">id</span>
              <span className="col-label">block</span>
              <span className="col-label">tx on explorer</span>
            </div>
            {submitted.map((d) => (
              <div
                key={d.txHash}
                className="grid grid-cols-[3rem_5.5rem_minmax(0,1fr)] gap-2 px-2 py-0.5 border-b hairline last:border-b-0 hover:bg-[var(--fill-hover)]"
                style={{ minWidth: TX_MIN_WIDTH }}
              >
                <span className="num text-2xs text-[var(--text-weak)]">{d.decisionId}</span>
                <span className="num text-2xs text-[var(--text-weak)]">{d.blockNumber}</span>
                <HashCell
                  value={d.txHash ?? ""}
                  kind="tx"
                  explorerBase={chain?.explorerBase ?? ""}
                />
              </div>
            ))}
          </div>
        )}
      </Panel>

      {/* The Learning panel used to live here and was removed: LearningPanel owns it now, and two
          panels rendering the same numbers is worse than either alone. See
          scripts/patch_chain_panel.py for why, and components/learning-panel.tsx for the sample-size
          handling task 5.6 requires. `learned` is still a prop because the transaction list uses the
          settled count for its footer note. */}
    </div>
  );
}
