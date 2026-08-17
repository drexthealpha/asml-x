/**
 * RWA versus crypto comparator, task 5.4.
 *
 * THE ARGUMENT THIS PANEL MAKES: the same order, at the same moment, against two markets. When the
 * verdicts differ, the RWA refusal names an RWA-specific cause. That is what separates a risk layer
 * from a global brake, and it is why the HEALTHY state is a required artifact rather than a nicety:
 * a layer that refuses in every state proves nothing about whether it is reading the instrument.
 *
 * Every verdict here was produced by the risk engine against the live vault on chain 1952 and
 * captured by `bash scripts/90-comparator-states.sh`. This component renders the capture; it does not
 * evaluate anything, so it cannot disagree with the engine.
 *
 * PATTERNS APPLIED (evidence/ui-study.md):
 * - Two columns of the same shape for a like-for-like comparison, the same discipline as their bid
 *   and ask columns sharing one row geometry (`orderbook-panel.tsx:87-101`).
 * - 12px `tabular-nums` rows at `py-0.5 px-2`, uppercase tracked labels (`orderbook-row.tsx:34`,
 *   `orderbook-panel.tsx:104`).
 * - State selector as plain hairline-bordered buttons beside the content they change, not a toolbar
 *   (`orderbook-panel.tsx:106-137`).
 * - Distinct empty and error sentences naming the file (`orderbook-panel.tsx:151-153`).
 */

import { useState } from "react";
import type { ComparatorData, ComparatorState, Load } from "../lib/data";
import { Panel, PanelEmpty, PanelError, cn } from "./primitives";

function Verdict({ label, verdict, detail }: { label: string; verdict: string; detail: string }) {
  const approved = verdict === "APPROVED";
  return (
    <div className="flex-1 min-w-0 border hairline">
      <div className="px-2 py-0.5 border-b hairline">
        <span className="col-label">{label}</span>
      </div>
      <div className="px-2 py-1">
        <span
          className="num text-2xs"
          style={{ color: approved ? "var(--status-long)" : "var(--status-short)" }}
        >
          {verdict}
        </span>
        {detail ? (
          <p className="mt-1 text-xs" style={{ color: "var(--status-short)" }}>
            {detail.replace(/^:\s*/, "")}
          </p>
        ) : null}
      </div>
    </div>
  );
}

function Fact({ label, value, tone }: { label: string; value: string; tone?: string }) {
  return (
    <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-2 py-0.5 border-b hairline last:border-b-0">
      <span className="text-2xs truncate text-[var(--text-weak)]">{label}</span>
      <span className="num text-2xs text-right" style={tone ? { color: tone } : undefined}>
        {value}
      </span>
    </div>
  );
}

export function ComparatorPanel({ data }: { data: Load<ComparatorData> }) {
  const [active, setActive] = useState(0);

  if (data.state === "error") {
    return (
      <Panel title="RWA vs crypto, same order">
        <PanelError source={data.source} reason={data.reason} />
      </Panel>
    );
  }
  if (data.state === "loading") {
    return (
      <Panel title="RWA vs crypto, same order">
        <PanelEmpty what="the comparator capture" />
      </Panel>
    );
  }

  const states = data.value.states;
  const s: ComparatorState | undefined = states[active];

  return (
    <Panel
      title="RWA vs crypto, same order"
      meta={<span className="num">{states.length} captured states</span>}
    >
      <div className="shrink-0 flex items-center gap-1 px-2 py-1 border-b hairline">
        {states.map((st, i) => (
          <button
            key={st.name}
            type="button"
            onClick={() => setActive(i)}
            className={cn(
              "px-1.5 py-0 text-2xs uppercase tracking-wider border hairline",
              i === active
                ? "bg-[var(--bg-overlay)] text-[var(--text-strong)]"
                : "text-[var(--text-weak)] hover:bg-[var(--fill-hover)]",
            )}
            title={st.setup}
          >
            {st.name}
          </button>
        ))}
      </div>

      {!s ? (
        <PanelEmpty what="a captured state" />
      ) : !s.parsed ? (
        <PanelError
          source={`evidence/phase5/comparator/${s.name}.txt`}
          reason="the capture could not be parsed, so no verdict is shown rather than a guessed one"
        />
      ) : (
        <div className="flex-1 min-h-0 overflow-auto scroll-thin">
          <div className="px-2 py-1 border-b hairline">
            <p className="text-xs text-[var(--text-weak)]">
              Same order, both markets, block <span className="num">{s.block ?? "—"}</span>:{" "}
              <span className="num text-[var(--text-strong)]">{s.order}</span>
            </p>
            <p className="mt-0.5 text-xs text-[var(--text-weak)]">Setup: {s.setup}</p>
          </div>

          <div className="flex gap-1 p-1">
            <Verdict label="crypto market, tBASE/tQUOTE" verdict={s.crypto.verdict} detail={s.crypto.detail} />
            <Verdict label="RWA market, RWA/tQUOTE" verdict={s.rwa.verdict} detail={s.rwa.detail} />
          </div>

          <div className="px-2 py-0.5 border-y hairline">
            <span className="col-label">the vault state both verdicts were read against</span>
          </div>
          <Fact label="oracle age" value={`${s.vault.oracleAgeSecs ?? "—"} s`} />
          <Fact
            label="issuer paused"
            value={s.vault.paused === null ? "—" : s.vault.paused ? "PAUSED" : "no"}
            tone={s.vault.paused ? "var(--status-short)" : undefined}
          />
          <Fact label="seconds until redemption window" value={`${s.vault.secondsUntilWindow ?? "—"}`} />
          <Fact
            label="oracle vs market divergence"
            value={`${s.vault.divergenceBps ?? "—"} bps`}
            tone={(s.vault.divergenceBps ?? 0) > 300 ? "var(--status-short)" : undefined}
          />
          <Fact label="yield index" value={s.vault.yieldIndex ?? "—"} />

          <div className="px-2 py-0.5 border-y hairline">
            <span className="col-label">what this state proves</span>
          </div>
          <Fact
            label="the two markets treated the order differently"
            value={s.divergentTreatment ? "yes" : "no"}
            tone={s.divergentTreatment ? "var(--status-warn)" : "var(--status-long)"}
          />
          <Fact
            label="the RWA refusal names an RWA-specific cause"
            value={s.rwaSpecificReason ? "yes" : "not applicable"}
            tone={s.rwaSpecificReason ? "var(--status-warn)" : undefined}
          />
          <p className="px-2 py-1 text-xs text-[var(--text-weak)]">
            {s.divergentTreatment
              ? "A generic trading bot would have taken this order. The refusal came from reading the instrument, and it names which condition failed."
              : "Both markets agreed here, and that is the point of keeping this capture: an RWA layer that refused in every state would be a global brake rather than a risk control that reads the instrument."}
          </p>
          <p className="px-2 pb-1 text-xs text-[var(--text-weak)]">
            Captured by <span className="num">{data.value.generatedBy}</span> against the live vault.
            Raw capture: <span className="num">evidence/phase5/comparator/{s.name}.txt</span>
          </p>
        </div>
      )}
    </Panel>
  );
}
