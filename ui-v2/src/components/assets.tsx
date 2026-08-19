/**
 * Real-world assets, and where yield actually comes from.
 *
 * THIS ANSWERS "WHERE IS BTC". It was a fair question and the earlier answer was wrong. I said X
 * Layer had no real-world assets beyond dollar tokens, having only looked at the aggregator's
 * token list. Onchain OS carries WBTC and xBTC at ~$64,500 and ETH at ~$1,911 on this chain, with
 * an aggregated index price alongside each one.
 *
 * TWO PRICES PER ASSET, AND THAT IS THE POINT. `price` is derived from the DEX pools; `index` is
 * aggregated across sources. They are separate measurements, so the distance between them is
 * meaningful. Before this feed existed the "divergence check" compared a price to itself, which is
 * always zero and therefore always passes: a safety check that cannot fail is not a safety check.
 *
 * YIELD IS REAL AND NAMED. Aave V3 on X Layer, with the APY and TVL it actually reports. No
 * projections, no illustrative figures.
 */

import { Activity, CheckCircle2, ExternalLink, ShieldAlert, ShieldCheck, TrendingUp } from "lucide-react";
import {
  POLL,
  ago,
  apy,
  compact,
  loadChain,
  loadDetails,
  loadOos,
  money,
  usePolled,
  type DefiProduct,
  type Chain,
  type Details,
  type Oos,
  type OosToken,
} from "../lib/feed";
import { Badge, Card, Show } from "./ui";
import { MissingDetail, TokenDetailPanel } from "./token-detail";
import { useState } from "react";

/** How far apart the two sources are, and whether that matters. */
function Divergence({ t }: { t: OosToken }) {
  if (!t.divergence_bps) return null;
  const bps = Number.parseFloat(t.divergence_bps);
  if (!Number.isFinite(bps)) return null;

  // 300 bps is the band the deployed RwaRiskGuard enforces, read from the contract by
  // scripts/okx_rwa.py rather than assumed here.
  const wide = Math.abs(bps) > 300;
  return wide ? (
    <Badge icon={ShieldAlert} tone="critical">
      {bps.toFixed(1)} bps apart, trading stopped
    </Badge>
  ) : (
    <Badge icon={CheckCircle2} tone="approved">
      two sources agree, {Math.abs(bps).toFixed(1)} bps apart
    </Badge>
  );
}

function AssetRow({ t, onOpen }: { t: OosToken; onOpen: (s: string) => void }) {
  const price = money(t.price);
  const change = t.change_24h ? Number.parseFloat(t.change_24h) : null;

  return (
    <button
      type="button"
      onClick={() => onOpen(t.symbol)}
      className="w-full text-left px-4 py-3 border-b hair last:border-b-0 hover:bg-raised"
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-sm text-ink font-medium">{t.symbol}</span>
        <div className="text-right">
          {price ? (
            <span className="num text-sm text-ink">${price}</span>
          ) : (
            <span className="text-xs text-ink-faint">no price</span>
          )}
          {change !== null && Number.isFinite(change) ? (
            <div
              className={`num text-xs ${change >= 0 ? "text-approved" : "text-critical"}`}
            >
              {change >= 0 ? "+" : ""}
              {change.toFixed(2)}% today
            </div>
          ) : null}
        </div>
      </div>

      <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-ink-faint">
        {t.index_price ? (
          <span className="num">reference ${money(t.index_price)}</span>
        ) : null}
        {t.liquidity ? <span>{compact(t.liquidity)} available to trade</span> : null}
        {t.pools?.length ? (
          <span className="truncate">{t.pools.map((p) => p.dex).filter(Boolean).join(", ")}</span>
        ) : null}
      </div>

      <div className="mt-2 flex flex-wrap gap-2">
        <Divergence t={t} />
        {t.honeypot === true ? (
          <Badge icon={ShieldAlert} tone="critical">
            unsafe contract
          </Badge>
        ) : t.honeypot === false ? (
          <Badge icon={ShieldCheck} tone="approved">
            contract checked
          </Badge>
        ) : null}
      </div>
    </button>
  );
}

function YieldRow({ p }: { p: DefiProduct }) {
  const rate = apy(p.apy);
  return (
    <div className="px-4 py-3 border-b hair last:border-b-0 flex items-baseline justify-between gap-3">
      <div className="min-w-0">
        <div className="text-sm text-ink truncate">{p.platform}</div>
        <div className="text-xs text-ink-faint">
          {compact(p.tvl)} deposited · {p.group === "LENDING" ? "lending" : "earn"}
        </div>
      </div>
      <div className="text-right shrink-0">
        <div className="num text-sm text-approved">{rate ?? "—"}</div>
        <div className="text-xs text-ink-faint">per year</div>
      </div>
    </div>
  );
}

export function Assets() {
  const oos = usePolled<Oos>(loadOos, POLL.oos);
  const details = usePolled<Details>(loadDetails, POLL.detail);
  const chain = usePolled<Chain>(loadChain, 300000);
  const [open, setOpen] = useState<string | null>(null);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6 grid gap-4 lg:grid-cols-[minmax(0,1fr)_24rem]">
      <div className="min-w-0 flex flex-col gap-4">
        <Card
          title="Real-world assets on X Layer"
          meta={
            oos.state === "ready" ? (
              <span className="flex items-center gap-1.5">
                <Activity
                  size={11}
                  className={oos.freshness.live ? "text-approved pulse" : "text-shielded"}
                />
                {oos.freshness.live ? "live" : (ago(oos.value.fetched_at_utc) ?? "")}
              </span>
            ) : null
          }
        >
          <div className="px-4 py-3 border-b hair">
            <p className="text-xs text-ink-soft leading-relaxed">
              Bitcoin, Ethereum and dollar tokens, tradable on this chain. Each is priced twice, by
              the pools and by an independent reference. When the two disagree by more than the
              limit, the agent stops trading it.
            </p>
          </div>
          <Show feed={oos} what="asset prices">
            {(o) =>
              o.tokens.length === 0 ? (
                <p className="px-4 py-6 text-sm text-ink-faint">
                  No asset prices returned on this refresh.
                </p>
              ) : (
                <>
                  {o.tokens.map((t) => (
                    <AssetRow key={t.address} t={t} onOpen={setOpen} />
                  ))}
                </>
              )
            }
          </Show>
        </Card>
      </div>

      <aside className="flex flex-col gap-4">
        <Card title="Earn on your deposit" meta={<TrendingUp size={13} />}>
          <div className="px-4 py-3 border-b hair">
            <p className="text-xs text-ink-soft leading-relaxed">
              Live lending and savings products on X Layer. The rate and the amount already
              deposited are what these platforms report right now.
            </p>
          </div>
          <Show feed={oos} what="yield products">
            {(o) => {
              const all = [...o.defi.earn, ...o.defi.lending, ...o.defi.pools];
              return all.length === 0 ? (
                <p className="px-4 py-6 text-sm text-ink-faint">
                  No products available on this chain right now.
                </p>
              ) : (
                <>
                  {all.map((p, i) => (
                    <YieldRow key={`${p.id}-${i}`} p={p} />
                  ))}
                  <div className="px-4 py-3">
                    <a
                      href="https://www.oklink.com/x-layer"
                      target="_blank"
                      rel="noreferrer noopener"
                      className="text-xs text-telemetry hover:underline inline-flex items-center gap-1"
                    >
                      View on the explorer
                      <ExternalLink size={10} />
                    </a>
                  </div>
                </>
              );
            }}
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
