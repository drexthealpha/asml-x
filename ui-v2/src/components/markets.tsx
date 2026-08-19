/**
 * Markets. A real price series, and the real-world assets on this chain.
 *
 * ON THE MISSING ASSET CLASSES, stated on the screen rather than hidden. There is no tokenized
 * gold, silver, or equity index on X Layer. Showing a gold price fetched from elsewhere would put
 * a number in front of someone that they cannot trade here and the vault cannot hold. The page
 * says so plainly and shows what IS real: dollar tokens backed by treasuries and cash, whose
 * distance from a dollar is a live, measurable risk on this exact chain.
 */

import { useEffect, useRef, useState } from "react";
import { createChart, AreaSeries, type IChartApi } from "lightweight-charts";
import { Activity, CheckCircle2, ShieldAlert, ShieldCheck } from "lucide-react";
import {
  POLL,
  ago,
  loadChain,
  loadDetails,
  loadMarket,
  loadRwa,
  money,
  usePolled,
  type Chain,
  type Details,
  type Market,
  type Rwa,
} from "../lib/feed";
import { Badge, Card, Show } from "./ui";
import { MissingDetail, TokenDetailPanel } from "./token-detail";

const TELEMETRY = "#3b82f6";

function PriceChart({ m }: { m: Market }) {
  const box = useRef<HTMLDivElement | null>(null);
  const [hover, setHover] = useState<string | null>(null);

  useEffect(() => {
    if (!box.current || m.candles.length === 0) return;
    const c: IChartApi = createChart(box.current, {
      autoSize: true,
      layout: {
        background: { color: "transparent" },
        textColor: "#71717a",
        fontSize: 11,
        attributionLogo: false,
      },
      grid: {
        vertLines: { color: "rgba(255,255,255,0.03)" },
        horzLines: { color: "rgba(255,255,255,0.03)" },
      },
      rightPriceScale: { borderColor: "rgba(255,255,255,0.06)" },
      timeScale: { borderColor: "rgba(255,255,255,0.06)", timeVisible: true },
      crosshair: { mode: 1 },
    });
    const s = c.addSeries(AreaSeries, {
      lineColor: TELEMETRY,
      lineWidth: 2,
      topColor: "rgba(59,130,246,0.18)",
      bottomColor: "rgba(59,130,246,0.01)",
      priceLineVisible: false,
    });
    s.setData(m.candles.map((k) => ({ time: k.t as never, value: Number.parseFloat(k.c) })));
    c.timeScale().fitContent();

    // The hover readout sits below the chart rather than floating, so it cannot fall off the edge
    // of a narrow screen.
    c.subscribeCrosshairMove((p) => {
      const v = p.seriesData.get(s) as { value?: number } | undefined;
      setHover(v?.value === undefined ? null : `$${v.value.toFixed(4)}`);
    });
    return () => c.remove();
  }, [m]);

  return (
    <Card
      title={`${m.pair.instId} price`}
      meta={hover ? <span className="num text-ink">{hover}</span> : <span>hover to read</span>}
    >
      <div className="px-4 pt-4">
        <div className="num text-3xl text-ink">${money(m.pair.last)}</div>
        <div className="text-xs text-ink-faint mt-1">
          24 hour range ${money(m.pair.low24h)} to ${money(m.pair.high24h)}
        </div>
      </div>
      <div ref={box} style={{ height: 300 }} className="mt-2" />
      <div className="grid grid-cols-3 border-t hair">
        <div className="px-4 py-3 border-r hair">
          <div className="text-xs text-ink-faint">Buy price</div>
          <div className="num text-sm text-ink mt-0.5">${money(m.pair.ask)}</div>
        </div>
        <div className="px-4 py-3 border-r hair">
          <div className="text-xs text-ink-faint">Sell price</div>
          <div className="num text-sm text-ink mt-0.5">${money(m.pair.bid)}</div>
        </div>
        <div className="px-4 py-3">
          <div className="text-xs text-ink-faint">How much it moves</div>
          <div className="num text-sm text-ink mt-0.5">{m.volatility.realized_bps_1m} bps</div>
        </div>
      </div>
    </Card>
  );
}

function RwaPanel({ r, onOpen }: { r: Rwa; onOpen: (s: string) => void }) {
  return (
    <Card
      title="Real-world assets"
      meta={<span>{ago(r.fetched_at_utc)}</span>}
    >
      <div className="px-4 py-3 border-b hair">
        <p className="text-xs text-ink-soft leading-relaxed">
          These tokens are backed by real assets: government debt, cash reserves, and collateral.
          Each should be worth one dollar. The agent stops trading one that drifts too far from
          that.
        </p>
      </div>

      {r.instruments.map((i) => {
        const price = money(i.price);
        const off = i.divergence_bps ? Number.parseFloat(i.divergence_bps) : null;
        return (
          <button
            key={i.symbol}
            type="button"
            onClick={() => onOpen(i.symbol)}
            className="w-full text-left px-4 py-3 border-b hair hover:bg-raised"
          >
            <div className="flex items-baseline justify-between gap-3">
              <span className="text-sm text-ink font-medium">{i.symbol}</span>
              {price ? (
                <span className="num text-sm text-ink">${price}</span>
              ) : (
                <span className="text-xs text-ink-faint">no price</span>
              )}
            </div>
            <p className="text-xs text-ink-faint mt-1 leading-relaxed">{i.plain}</p>
            <div className="mt-2">
              {i.status === "within_band" ? (
                <Badge icon={CheckCircle2} tone="approved">
                  {off !== null && Math.abs(off) < 1
                    ? "holding its value"
                    : `${off?.toFixed(1)} bps from a dollar`}
                </Badge>
              ) : i.status === "breached" ? (
                <Badge icon={ShieldAlert} tone="critical">
                  off by {off?.toFixed(0)} bps, trading stopped
                </Badge>
              ) : i.status === "not_peg_checked" ? (
                <Badge icon={ShieldCheck} tone="muted">
                  earns yield, not a fixed dollar
                </Badge>
              ) : (
                <Badge icon={ShieldAlert} tone="shielded">
                  cannot be traded here
                </Badge>
              )}
            </div>
          </button>
        );
      })}

      {/* The limitation, on the product surface, because a person choosing what to trade needs to
          know what is absent before they go looking for it. */}
      <div className="px-4 py-3">
        <p className="text-xs text-ink-faint leading-relaxed">{r.absent_asset_classes}</p>
      </div>
    </Card>
  );
}

export function Markets() {
  // POLLED, not fetched once. A market panel whose number never changes is indistinguishable
  // from a hardcoded one, and that is exactly how this looked.
  const market = usePolled<Market>(loadMarket, POLL.market);
  const rwa = usePolled<Rwa>(loadRwa, POLL.rwa);
  const details = usePolled<Details>(loadDetails, POLL.detail);
  const chain = usePolled<Chain>(loadChain, 300000);
  const [open, setOpen] = useState<string | null>(null);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6 grid gap-4 lg:grid-cols-[minmax(0,1fr)_24rem]">
      <div className="min-w-0">
        <Show feed={market} what="the price chart">
          {(m) => <PriceChart m={m} />}
        </Show>
        {market.state === "ready" ? (
          <p className="flex items-center gap-2 text-xs text-ink-faint mt-3 px-1">
            {/* THE PULSE IS DRIVEN BY THE FEED, not decoration. It pulses only while the server
                is actually refreshing; a stale feed says so and stops pretending. */}
            <Activity
              size={12}
              className={market.freshness.live ? "text-approved pulse" : "text-shielded"}
            />
            {market.freshness.live
              ? `Live from OKX, refreshed every ${POLL.market / 1000}s`
              : `Not refreshing right now. This price is from ${ago(market.value.fetched_at_utc) ?? "an earlier fetch"}.`}
          </p>
        ) : null}
      </div>
      <Show feed={rwa} what="real-world asset prices">
        {(r) => <RwaPanel r={r} onOpen={setOpen} />}
      </Show>

      {/* Every row on this surface opens the same panel as every other surface. One detail view,
          reached from anywhere a token is named, so a person never has to learn where a given
          asset "lives" in the app. */}
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
