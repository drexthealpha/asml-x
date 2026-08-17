/**
 * The app shell, task 4.1.
 *
 * PATTERNS APPLIED (evidence/ui-study.md section 1):
 * - Height is derived from the VIEWPORT minus the chrome (CHROME.BODY_HEIGHT), never from content.
 *   Sizing to content is what produces the dead regions this project is told to avoid
 *   (main-workspace.tsx:26 does `max(calc(100dvh - 9.375rem), minPx)`).
 * - `flex-1 min-h-0 flex flex-col` on every container, `shrink-0` on chrome
 *   (main-workspace.tsx:36,45,48).
 * - Panel splits come from PANEL_LAYOUT constants (their config/layout.ts:3-19).
 *
 * ONE POLLING LOOP for all three sources, which is the reduction of their single staleness
 * watchdog (staleness.ts:20-109): N panels, one timer. Each source keeps its own load state, so a
 * failure in one leaves the others rendering.
 */

import { useCallback, useEffect, useMemo, useState } from "react";
import { BrainPanel } from "./components/brain-panel";
import { ChainPanel } from "./components/chain-panel";
import { ComparatorPanel } from "./components/comparator-panel";
import { EvidencePanel } from "./components/evidence-panel";
import { JournalPanel } from "./components/journal-panel";
import { MetricsPanel } from "./components/metrics-panel";
import { RevenuePanel } from "./components/revenue-panel";
import { MainnetPanel } from "./components/mainnet-panel";
import { LearningPanel } from "./components/learning-panel";
import { RefusalLedger } from "./components/refusal-ledger";
import { ResizableHandle, ResizablePanel, ResizablePanelGroup } from "./components/resizable";
import { RiskPanel } from "./components/risk-panel";
import { ViewTabs, type ViewId } from "./components/view-tabs";
import { PersonalView } from "./components/personal-view";
import { ExitBar } from "./components/exit-bar";
import { mark } from "./lib/flow-timing";
import { EXIT_BAR_REM } from "./config/layout";
import { TopBar } from "./components/top-bar";
// PANEL_LAYOUT's MAIN split constants are no longer used here: the two-column split moved into each
// view, and each view sets its own sidebar width because the sidebar content differs per view. The
// per-panel min-heights are still read inside the panels themselves.

import {
  DATA_LIMITS,
  loadDeployments,
  loadJournal,
  loadLearnedState,
  loadComparator,
  loadMetrics,
  type ChainConfig,
  type ComparatorData,
  type JournalLoad,
  type LearnedState,
  type Load,
  type Metrics,
} from "./lib/data";

// TASK 10.1: the timing origin. Module scope, so it is stamped when the bundle
// evaluates rather than after React has mounted and done work worth measuring.
mark("first_paint");

const CHROME_REM = 5;

/**
 * Chrome grows by the exit bar when it is present, task 9.5.
 *
 * `main` is sized as `100dvh - chrome`. A bar added to the chrome without this adjustment pushes the
 * bottom of the content past the viewport, which is the clipping defect the resizable-panel port
 * exists to prevent. Reintroducing it through a hardcoded 5 would be careless.
 */
function chromeRem(hasExitBar: boolean): number {
  return CHROME_REM + (hasExitBar ? EXIT_BAR_REM : 0);
}
const BODY_FLOOR_PX = 416;

function errOf<T>(l: Load<T>) {
  return l.state === "error" ? { source: l.source, reason: l.reason } : undefined;
}

export default function App() {
  const [journal, setJournal] = useState<Load<JournalLoad>>({ state: "loading" });
  const [learned, setLearned] = useState<Load<LearnedState>>({ state: "loading" });
  const [chain, setChain] = useState<Load<ChainConfig>>({ state: "loading" });
  const [metrics, setMetrics] = useState<Load<Metrics>>({ state: "loading" });
  const [comparator, setComparator] = useState<Load<ComparatorData>>({ state: "loading" });
  const [view, setView] = useState<ViewId>("you");
  const [exitBarVisible, setExitBarVisible] = useState(false);
  const [nowMs, setNowMs] = useState(() => Date.now());
  const [selectedId, setSelectedId] = useState<number | null>(null);

  const refresh = useCallback(async () => {
    const [j, l, c, m, cmp] = await Promise.all([
      loadJournal(),
      loadLearnedState(),
      loadDeployments(),
      loadMetrics(),
      loadComparator(),
    ]);
    setJournal(j);
    setLearned(l);
    setChain(c);
    setMetrics(m);
    setComparator(cmp);
    setNowMs(Date.now());
  }, []);

  useEffect(() => {
    void refresh();
    const poll = setInterval(() => void refresh(), DATA_LIMITS.pollIntervalMs);
    // A second, cheaper tick so the freshness readout counts up between polls rather than
    // jumping. It touches only `nowMs`, so no source is re-read.
    const tick = setInterval(() => setNowMs(Date.now()), 1_000);
    return () => {
      clearInterval(poll);
      clearInterval(tick);
    };
  }, [refresh]);

  const decisions = journal.state === "ok" ? journal.value.decisions : [];
  const chainValue = chain.state === "ok" ? chain.value : null;
  const learnedValue = learned.state === "ok" ? learned.value : null;

  const selected = useMemo(() => {
    const agent = decisions.filter((d) => !d.isBaseline);
    if (selectedId === null) return agent.length > 0 ? agent[0] : null;
    return decisions.find((d) => d.decisionId === selectedId) ?? null;
  }, [decisions, selectedId]);

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <TopBar
        decisions={journal.state === "ok" ? decisions : null}
        chain={chainValue}
        learned={learnedValue}
        fetchedAtMs={journal.state === "ok" ? journal.fetchedAtMs : null}
        nowMs={nowMs}
        malformedLines={journal.state === "ok" ? journal.value.malformedLines : null}
        baselineRows={journal.state === "ok" ? journal.value.baselineRows : null}
        anomalousRows={
          journal.state === "ok"
            ? decisions.filter((d) => d.anomalies.length > 0).length
            : null
        }
      />

      <ViewTabs active={view} onSelect={setView} />

      {/* TASK 9.5: Pause and Withdraw on EVERY route, not only the personal view. A user
          with money in the vault who is reading the Risk tab should not have to navigate
          anywhere to get out. Renders nothing when there is no position. */}
      <ExitBar onVisible={setExitBarVisible} />

      {/* FOUR VIEWS, NOT ONE SCREEN.
          The earlier layout forced eight panels onto one 1920x1080 surface. Each shrank to a strip,
          and the layout was reshuffled repeatedly to chase a density metric, which is solving the
          wrong problem. HypeTerminal tabs alternative views of the same question
          (orderbook-panel.tsx:87-101) and routes between whole workspaces; the study cited that and
          the first layout ignored it.

          Each view keeps the journal available, because the journal is the spine: every other panel
          answers a question ABOUT a decision, so the decision selector has to be reachable from
          every surface. */}
      {/* WORKSPACE, ported from their main-workspace.tsx rather than hand-rolled.
          `flex-wrap` was the previous approach and it CLIPPED: at a 632px viewport `main` measured
          clientHeight 466 against scrollHeight 6945, with 683 elements past the viewport edge and
          overflow-hidden hiding all of it. Their pattern is resizable panels side by side plus a body
          height of max(viewport - chrome, floor), so a short viewport scrolls the page instead of
          cutting content off. Chrome here is the header, the tab row and the footer, so 5rem, and the
          floor is 26rem. */}
      <main
        className="flex-1 min-h-0 overflow-y-auto overflow-x-hidden p-1"
        style={{ height: `max(calc(100dvh - ${chromeRem(exitBarVisible)}rem), ${BODY_FLOOR_PX}px)` }}
      >
        {/* `orientation`, not `direction`. react-resizable-panels renamed it in v4 and horizontal is
            the default, so it is omitted rather than passed redundantly. */}
        <ResizablePanelGroup className="gap-1" style={{ minHeight: `${BODY_FLOOR_PX}px` }}>
        {view === "you" ? (
          // The landing surface. One panel at full width: there is nothing to put beside Connect
          // that a disconnected visitor could act on, and filling the space would be the
          // "empty regions above baseline" failure this project names explicitly.
          <ResizablePanel defaultSize={100} minSize={30} className="flex flex-col min-h-0">
            <PersonalView />
          </ResizablePanel>
        ) : view === "decide" ? (
          <>
            {/* The brain takes the whole wide column: a decision has 53 candidates, so it fills 900px
                without help. The right column puts evidence ABOVE the journal, evidence sized to its
                content and the journal taking the remainder. The first arrangement had evidence alone
                in the right column and measured a 520x728 void beneath its two rows, 26.3% of the
                viewport. The panel with rows to spare belongs where the void was. */}
            <ResizablePanel defaultSize={62} minSize={35} className="flex flex-col min-h-0">
              <BrainPanel decision={selected} error={errOf(journal)} />
            </ResizablePanel>
            <ResizableHandle withHandle />
            <ResizablePanel defaultSize={38} minSize={22} className="flex flex-col min-h-0 gap-1">
              <div className="shrink-0 flex flex-col" style={{ maxHeight: "40%" }}>
                <EvidencePanel decision={selected} error={errOf(journal)} />
              </div>
              <div className="flex-1 min-h-0 flex flex-col">
                <JournalPanel
                  decisions={decisions}
                  chain={chainValue}
                  selectedId={selected?.decisionId ?? null}
                  onSelect={setSelectedId}
                  error={errOf(journal)}
                  totalLines={journal.state === "ok" ? journal.value.totalLines : null}
                />
              </div>
            </ResizablePanel>
          </>
        ) : view === "risk" ? (
          <>
            {/* The ledger takes the wide column because it has 2,236 rows; the summary is a few
                totals and two bars, so it takes the narrow one. Sizing them the other way round is
                what left this view 41% empty when it was first measured. */}
            <ResizablePanel defaultSize={68} minSize={40} className="flex flex-col min-h-0">
              <RefusalLedger decisions={decisions} error={errOf(journal)} />
            </ResizablePanel>
            <ResizableHandle withHandle />
            {/* The column scrolls. It stacks a content-sized risk summary above a flexible journal, and
                when the summary needs more than the column has (measured 565px of content in a 458px
                panel at a 632px viewport) react-resizable-panels hides the overflow and the remainder
                is unreachable. */}
            <ResizablePanel
              defaultSize={32}
              minSize={20}
              className="flex flex-col min-h-0 gap-1 overflow-y-auto scroll-thin"
            >
              <div className="shrink-0 flex flex-col">
                <RiskPanel decisions={decisions} error={errOf(journal)} />
              </div>
              <div className="flex-1 min-h-0 flex flex-col">
                <JournalPanel
                  decisions={decisions}
                  chain={chainValue}
                  selectedId={selected?.decisionId ?? null}
                  onSelect={setSelectedId}
                  error={errOf(journal)}
                  totalLines={journal.state === "ok" ? journal.value.totalLines : null}
                />
              </div>
            </ResizablePanel>
          </>
        ) : view === "chain" ? (
          <>
            {/* Metrics is sized to its CONTENT, not given the flexible height. Making its rows two-up
                halved the height it needs, and leaving it on `flex-1` opened a 824x384 void beneath
                the content, 22% of the viewport. Learning sits under it because the two together
                fill the column, and both are compact by nature. */}
            <ResizablePanel defaultSize={58} minSize={32} className="flex flex-col min-h-0 gap-1">
              <div className="shrink-0 flex flex-col" style={{ maxHeight: "58%" }}>
                <MetricsPanel metrics={metrics} />
                <RevenuePanel metrics={metrics} />
                <MainnetPanel />
              </div>
              <div className="flex-1 min-h-0 flex flex-col">
                <LearningPanel
                  learned={learnedValue}
                  decisions={decisions}
                  error={errOf(learned)}
                />
              </div>
            </ResizablePanel>
            {/* Contracts and the transaction list. The transaction list grows with every run, so it
                takes the flexible height inside ChainPanel. */}
            <ResizableHandle withHandle />
            <ResizablePanel defaultSize={42} minSize={24} className="flex flex-col min-h-0">
              <ChainPanel chain={chainValue} decisions={decisions} chainError={errOf(chain)} />
            </ResizablePanel>
          </>
        ) : view === "rwa" ? (
          <>
            {/* The comparator takes the wide column: three states, two verdicts each, and the vault
                state behind them. The journal sits beside it so a reader can cross-check that the
                agent kept trading the crypto market while the RWA market was refusing. */}
            <ResizablePanel defaultSize={62} minSize={35} className="flex flex-col min-h-0">
              <ComparatorPanel data={comparator} />
            </ResizablePanel>
            <ResizableHandle withHandle />
            <ResizablePanel defaultSize={38} minSize={22} className="flex flex-col min-h-0">
              <JournalPanel
                decisions={decisions}
                chain={chainValue}
                selectedId={selected?.decisionId ?? null}
                onSelect={setSelectedId}
                error={errOf(journal)}
                totalLines={journal.state === "ok" ? journal.value.totalLines : null}
              />
            </ResizablePanel>
          </>
        ) : (
          <>
            {/* LEARN was folded into CHAIN and this branch is unreachable from the tab bar. Kept as
                the explicit fallback for an unknown view id rather than rendering nothing. */}
            <ResizablePanel defaultSize={100} minSize={30} className="flex flex-col min-h-0">
              <LearningPanel
                learned={learnedValue}
                decisions={decisions}
                error={errOf(learned)}
              />
            </ResizablePanel>
          </>
        )}
        </ResizablePanelGroup>
      </main>

      {/* min-height, not a fixed h-6. Raising the prose to 14px made the sentence taller than 24px
          and it overflowed into the panel above it. */}
      <footer
        className="shrink-0 flex items-center justify-between gap-3 px-2 py-0.5 border-t hairline bg-[var(--bg-raised)]"
        style={{ minHeight: "1.5rem" }}
      >
        <span className="text-2xs text-[var(--text-weak)]">
          Every number on this screen is read from the agent's own output files. No value is
          generated by the UI, and a missing source renders as an error rather than a zero.
        </span>
        <span className="num text-2xs text-[var(--text-weak)]">
          poll {DATA_LIMITS.pollIntervalMs / 1000}s
        </span>
      </footer>
    </div>
  );
}
