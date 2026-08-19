/**
 * ASML-X. Trade real tokens on X Layer, with an agent that cannot exceed your limit.
 *
 * WHAT CHANGED AND WHY. The previous app was a debug console wearing a product's name: it opened
 * on a decision journal, put evidence identifiers and sample sizes on the primary surface, and
 * described itself in the vocabulary of its own construction. A person who wants to trade could
 * not tell what it did.
 *
 * TWO SURFACES, because there are two questions: what can I trade and what does it cost (Trade),
 * and what is the market doing (Markets). Everything that served the project rather than the
 * person is gone from the frontend entirely.
 */

import { useEffect, useState } from "react";
import { Activity, ExternalLink } from "lucide-react";
import { loadChain, type Chain, type Feed } from "./lib/feed";
import { Trade } from "./components/trade";
import { Markets } from "./components/markets";
import { Assets } from "./components/assets";
import { IntelView } from "./components/intel";
import { AgentView } from "./components/agent";
import { Limits } from "./components/limits";
import { Machine } from "./components/machine";
import { cn } from "./components/ui";

type Tab = "limits" | "trade" | "agent" | "assets" | "markets" | "intel" | "machine";

/** The reticle from the brand spec: crosshair, ring, core, live pulse. Drawn, not an image. */
function Emblem({ live }: { live: boolean }) {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true">
      <circle
        cx="10"
        cy="10"
        r="8"
        fill="none"
        stroke="currentColor"
        strokeWidth="1"
        strokeDasharray="3 2"
        className={live ? "pulse" : undefined}
      />
      <path d="M10 1v4M10 15v4M1 10h4M15 10h4" stroke="currentColor" strokeWidth="1" />
      <circle cx="10" cy="10" r="3" fill="currentColor" opacity="0.9" />
    </svg>
  );
}

export default function App() {
  const [tab, setTab] = useState<Tab>("limits");
  const [chain, setChain] = useState<Feed<Chain>>({ state: "loading" });

  useEffect(() => {
    void loadChain().then(setChain);
  }, []);

  const net = chain.state === "ready" ? chain.value : null;

  return (
    <div className="min-h-full flex flex-col bg-bg">
      <header className="border-b hair bg-surface sticky top-0 z-10">
        {/*
          THE HEADER AT 375px, measured rather than assumed.
          Five tabs plus the brand plus the network badge came to 539px against a 375px viewport:
          164px of horizontal overflow on every surface, which is the defect that makes a page feel
          broken before a word of it is read.

          The fix is layout, not deletion. The brand and the network badge stay on one row; the
          tabs move to their own scrollable row below on narrow screens and sit inline from `sm`
          up. Nothing is hidden: a tab a person cannot reach is worse than a tab they must scroll
          to.
        */}
        <div className="mx-auto w-full max-w-6xl px-4 py-2 sm:h-14 sm:py-0 flex flex-wrap sm:flex-nowrap items-center gap-x-4 gap-y-1">
          <div className="flex items-center gap-2 text-approved shrink-0">
            <Emblem live={net !== null} />
            <span className="text-sm font-semibold tracking-tight text-ink">ASML-X</span>
          </div>

          <nav
            className="order-3 sm:order-none w-full sm:w-auto flex items-center gap-1 overflow-x-auto"
            aria-label="Sections"
          >
            {(
              [
                ["limits", "Your limits"],
                ["trade", "Trade"],
                ["agent", "Your agent"],
                ["assets", "Assets"],
                ["markets", "Markets"],
                ["intel", "Insights"],
                ["machine", "Contracts"],
              ] as const
            ).map(([id, label]) => (
              <button
                key={id}
                type="button"
                onClick={() => setTab(id)}
                aria-current={tab === id ? "page" : undefined}
                className={cn(
                  "px-3 py-1.5 rounded text-sm whitespace-nowrap shrink-0",
                  tab === id
                    ? "bg-raised text-ink"
                    : "text-ink-faint hover:text-ink hover:bg-raised/60",
                )}
              >
                {label}
              </button>
            ))}
          </nav>

          {/* The network, NAMED BY THE MANIFEST rather than by a string in this file. The old
              header printed "X Layer testnet" for any chain whose id matched, and kept saying so
              over mainnet blocks. */}
          <div className="ml-auto order-2 sm:order-none flex items-center gap-2 shrink-0">
            {net ? (
              <span className="flex items-center gap-1.5 text-xs text-ink-soft">
                <Activity size={12} className="text-approved pulse" />
                {net.chain_name}
              </span>
            ) : null}
          </div>
        </div>
      </header>

      <main className="flex-1">
        {tab === "limits" ? (
          <Limits onConnect={() => setTab("trade")} />
        ) : tab === "trade" ? (
          <Trade />
        ) : tab === "agent" ? (
          <AgentView />
        ) : tab === "assets" ? (
          <Assets />
        ) : tab === "machine" ? (
          <Machine />
        ) : tab === "intel" ? (
          <IntelView />
        ) : (
          <Markets />
        )}
      </main>

      {/*
        THE FOOTER, rebuilt.

        It previously carried a sentence about how the UI sources its numbers, which is a note the
        authors wrote to themselves. What belongs here is what a person needs in order to VERIFY
        and to LEAVE: the network and its id, the contracts holding the money with links to the
        public explorer, and the licence. That is the institutional standard: a footer is where you
        find the addresses, not where the product explains its own methodology.
      */}
      <footer className="border-t hair bg-surface mt-8">
        <div className="mx-auto w-full max-w-6xl px-4 py-6 grid gap-6 sm:grid-cols-[minmax(0,1fr)_auto]">
          <div className="min-w-0">
            <h3 className="text-xs text-ink-faint uppercase tracking-wider">Contracts</h3>
            {net ? (
              <ul className="mt-2 grid gap-1 sm:grid-cols-2">
                {net.deployments.map((d) => (
                  <li key={d.address} className="flex items-baseline gap-2 min-w-0">
                    <a
                      href={`${net.explorer_address_base}${d.address}`}
                      target="_blank"
                      rel="noreferrer noopener"
                      className="text-xs text-ink-soft hover:text-ink inline-flex items-center gap-1 shrink-0"
                    >
                      {d.name}
                      <ExternalLink size={10} />
                    </a>
                    <span className="num text-xs text-ink-faint truncate">
                      {d.address.slice(0, 10)}…{d.address.slice(-6)}
                    </span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-xs text-ink-faint mt-2">Loading contract addresses.</p>
            )}
          </div>

          <div className="text-xs text-ink-faint sm:text-right">
            {net ? (
              <p className="num">
                {net.chain_name} · chain {net.chain_id}
              </p>
            ) : null}
            <p className="mt-1">MIT licensed</p>
            <a
              href="https://github.com/drexthealpha/asml-x"
              target="_blank"
              rel="noreferrer noopener"
              className="mt-1 inline-flex items-center gap-1 hover:text-ink"
            >
              Source
              <ExternalLink size={10} />
            </a>
          </div>
        </div>
      </footer>
    </div>
  );
}
