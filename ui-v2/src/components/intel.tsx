/**
 * What informed money is doing, and what the market is saying about it.
 *
 * WHY THIS IS ON THE PRODUCT SURFACE. It is the only part of the app that answers "why", and it is
 * information a person cannot get from a price chart: which wallets that the data provider
 * classifies as smart money just bought something, and whether the conversation around an asset is
 * bullish or bearish.
 *
 * THE LIMIT IS STATED ON SCREEN, not buried. Sentiment moves the agent's CONFIDENCE and never its
 * limits. Putting a bullish reading next to a trading control invites the assumption that a good
 * mood can loosen a cap; it cannot, and the guarantee that it cannot is the whole point of this
 * product. So the note is rendered, not left in a docstring.
 *
 * COUNTS, NOT SCORES. Every figure here is a mention count or a wallet count that arrived in the
 * same response, so a reader can check the arithmetic rather than trust an index.
 */

import { Activity, Newspaper, ShieldCheck, TrendingDown, TrendingUp, Users } from "lucide-react";
import {
  POLL,
  ago,
  compact,
  loadChain,
  loadDetails,
  loadIntel,
  usePolled,
  type Chain,
  type Details,
  type Intel,
  type Sentiment,
  type SmartMoney,
} from "../lib/feed";
import { Badge, Card, Show } from "./ui";
import { MissingDetail, TokenDetailPanel } from "./token-detail";
import { useState } from "react";

/** 1 smart money, 2 KOL, 3 whale. The API's classification, named in plain words. */
function walletKind(t: string): string {
  return t === "1" ? "smart money" : t === "2" ? "known trader" : "large holder";
}

function SentimentRow({ s, onOpen }: { s: Sentiment; onOpen: (x: string) => void }) {
  const bull = Number.parseInt(s.bullish, 10) || 0;
  const bear = Number.parseInt(s.bearish, 10) || 0;
  const total = bull + bear + (Number.parseInt(s.neutral, 10) || 0);
  // Width from the actual counts. If total is zero the bar is absent rather than a full-width
  // block implying unanimous neutrality.
  const bullPct = total ? (bull / total) * 100 : 0;
  const bearPct = total ? (bear / total) * 100 : 0;

  return (
    <button
      type="button"
      onClick={() => onOpen(s.symbol)}
      className="w-full text-left px-4 py-3 border-b hair last:border-b-0 hover:bg-raised"
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-sm text-ink font-medium">{s.symbol}</span>
        <span className="text-xs text-ink-faint num">{s.mentions} mentions</span>
      </div>

      {total > 0 ? (
        <>
          <div className="mt-2 flex h-1.5 rounded overflow-hidden bg-raised" aria-hidden="true">
            <div style={{ width: `${bullPct}%` }} className="bg-approved" />
            <div style={{ width: `${bearPct}%` }} className="bg-critical" />
          </div>
          <div className="mt-1.5 flex items-center gap-3 text-xs">
            <span className="text-approved inline-flex items-center gap-1">
              <TrendingUp size={11} />
              {bull} positive
            </span>
            <span className="text-critical inline-flex items-center gap-1">
              <TrendingDown size={11} />
              {bear} negative
            </span>
            <span className="text-ink-faint ml-auto">{s.label}</span>
          </div>
        </>
      ) : (
        <p className="mt-1 text-xs text-ink-faint">Nothing being said about this right now.</p>
      )}
    </button>
  );
}

function SignalRow({ m, onOpen }: { m: SmartMoney; onOpen: (x: string) => void }) {
  const conc = m.top10_holder_percent ? Number.parseFloat(m.top10_holder_percent) : null;
  // Above 50% in ten wallets is a real concentration risk worth flagging before someone buys.
  const concentrated = conc !== null && conc > 50;

  return (
    <button
      type="button"
      onClick={() => m.symbol && onOpen(m.symbol)}
      className="w-full text-left px-4 py-3 border-b hair last:border-b-0 hover:bg-raised"
    >
      <div className="flex items-baseline justify-between gap-3">
        <div className="min-w-0">
          <span className="text-sm text-ink font-medium">{m.symbol ?? "unnamed token"}</span>
          {m.name && m.name !== m.symbol ? (
            <span className="text-xs text-ink-faint ml-2 truncate">{m.name}</span>
          ) : null}
        </div>
        <span className="num text-sm text-ink shrink-0">{compact(m.amount_usd)}</span>
      </div>

      <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-ink-faint">
        <span className="inline-flex items-center gap-1">
          <Users size={11} />
          {m.wallets} {walletKind(m.wallet_type)} wallets
        </span>
        {m.holders ? <span>{m.holders} holders</span> : null}
        {m.market_cap_usd ? <span>{compact(m.market_cap_usd)} size</span> : null}
      </div>

      {concentrated ? (
        <div className="mt-2">
          <Badge icon={Users} tone="shielded">
            top 10 wallets hold {conc?.toFixed(0)}%
          </Badge>
        </div>
      ) : null}
    </button>
  );
}

export function IntelView() {
  const intel = usePolled<Intel>(loadIntel, POLL.intel);
  const details = usePolled<Details>(loadDetails, POLL.detail);
  const chain = usePolled<Chain>(loadChain, 300000);
  const [open, setOpen] = useState<string | null>(null);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6 grid gap-4 lg:grid-cols-[minmax(0,1fr)_24rem]">
      <div className="min-w-0 flex flex-col gap-4">
        <Card
          title="What large wallets are buying"
          meta={
            intel.state === "ready" ? (
              <span className="flex items-center gap-1.5">
                <Activity
                  size={11}
                  className={intel.freshness.live ? "text-approved pulse" : "text-shielded"}
                />
                {intel.freshness.live ? "live" : (ago(intel.value.fetched_at_utc) ?? "")}
              </span>
            ) : null
          }
        >
          <div className="px-4 py-3 border-b hair">
            <p className="text-xs text-ink-soft leading-relaxed">
              Recent purchases by wallets with a track record. Shown so you can see what the agent
              sees, not as a recommendation.
            </p>
          </div>
          <Show feed={intel} what="wallet activity">
            {(i) =>
              i.smart_money.length === 0 ? (
                <p className="px-4 py-6 text-sm text-ink-faint">
                  No notable purchases on this chain in the last window.
                </p>
              ) : (
                <>
                  {i.smart_money.map((m, n) => (
                    <SignalRow key={`${m.address}-${n}`} m={m} onOpen={setOpen} />
                  ))}
                </>
              )
            }
          </Show>
        </Card>
      </div>

      <aside className="flex flex-col gap-4">
        <Card title="What people are saying" meta={<Newspaper size={13} />}>
          <Show feed={intel} what="market sentiment">
            {(i) => (
              <>
                {i.sentiment.map((s) => (
                  <SentimentRow key={s.symbol} s={s} onOpen={setOpen} />
                ))}
                {i.news.length > 0 ? (
                  <div className="px-4 py-3 border-t hair">
                    <ul className="grid gap-2">
                      {i.news.slice(0, 4).map((n, k) => (
                        <li key={k}>
                          <a
                            href={n.url}
                            target="_blank"
                            rel="noreferrer noopener"
                            className="text-xs text-ink-soft hover:text-ink leading-snug block"
                          >
                            {n.title}
                          </a>
                        </li>
                      ))}
                    </ul>
                  </div>
                ) : null}

                {/* The guarantee, next to the thing that might otherwise seem to threaten it. */}
                <div className="px-4 py-3 border-t hair flex items-start gap-2">
                  <ShieldCheck size={14} className="text-approved shrink-0 mt-0.5" />
                  <p className="text-xs text-ink-faint leading-relaxed">{i.usage_note}</p>
                </div>
              </>
            )}
          </Show>
        </Card>
      </aside>

      {open ? (
        details.state === "ready" && details.value.tokens[open] ? (
        <TokenDetailPanel
          t={details.value.tokens[open]}
          onClose={() => setOpen(null)}
            explorerBase={chain.state === "ready" ? chain.value.explorer_address_base : undefined}
          />
        ) : (
          // A row that opens nothing reads as broken. When a token has no record yet, say so and
          // give a way out, rather than swallowing the click.
          <MissingDetail symbol={open} onClose={() => setOpen(null)} />
        )
      ) : null}
    </div>
  );
}
