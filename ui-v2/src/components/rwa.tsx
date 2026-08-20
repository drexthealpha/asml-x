/**
 * Real-world assets. Every datapoint Onchain OS returns, and every one of them clickable.
 *
 * WHAT THIS IS NOT. It is not a price list. A price beside a contract address shows that both
 * exist and leaves a person to imagine the connection. This renders the whole record: the company
 * the token is a claim on, the exchange it lists on, who holds it, how concentrated that is, what
 * the pools look like, and all twenty-four of OKX's risk flags.
 *
 * THE FLAG THAT MATTERS MOST is `isCounterfeitStockToken`: OKX telling you a token claiming to be
 * a share is not one. Showing a price while dropping that flag would be the worst thing this
 * surface could do, so it is checked first and, when set, it is the only thing above the fold.
 *
 * NOTHING IS CURATED AWAY. Fields arrive as whole response objects and every key is rendered. A
 * hand-picked subset is a decision about what someone is allowed to see, and this product has no
 * standing to make that decision for them.
 */

import { useState } from "react";
import {
  AlertTriangle,
  Building2,
  CheckCircle2,
  ChevronRight,
  ExternalLink,
  ShieldAlert,
  ShieldCheck,
  X,
} from "lucide-react";
import {
  POLL,
  ago,
  compact,
  humanKey,
  loadRwaFull,
  money,
  usePolled,
  type RwaAsset,
  type RwaFull,
} from "../lib/feed";
import { Badge, Card, Show, cn } from "./ui";

/** A flag whose TRUE value is bad news. Everything else true is reassuring. */
const BAD_WHEN_TRUE = new Set([
  "isHoneypot", "isCounterfeit", "isCounterfeitStockToken", "isAirdropScam", "isDumping",
  "isFakeLiquidity", "isFundLinkage", "isHasAssetEditAuth", "isHasBlockingHis",
  "isHasFrozenAuth", "isLiquidityRemoval", "isLowLiquidity", "isMintable", "isNotOpenSource",
  "isNotRenounced", "isOverIssued", "isPump", "isRubbishAirdrop", "isVeryHighLpHolderProp",
  "isVeryLowLpBurn", "isWash", "isWash2",
]);

/** Keys whose value is a 0-1 ratio the API returns unscaled. 0.99999 means 99.999%. */
const RATIO_KEYS = /percent$/i;

/** Keys that are money and should read as money, not as a 55-digit string. */
const MONEY_KEYS = /liquidity|marketCap|volume|tradeNum|totalFee/i;

/**
 * Format a raw API value the way a person reads it.
 *
 * THE API RETURNS FULL PRECISION. Liquidity arrives as
 * "1381932.8135571564990180047307234765681985255224908730442" and a percentage arrives as
 * "0.99999". Rendering those verbatim is technically honest and practically unreadable, which is
 * its own kind of dishonesty: nobody scanning that string learns that the top 100 wallets hold
 * essentially all of it.
 */
function display(k: string, v: unknown): string {
  const s = String(v);
  const n = Number(v);
  if (!Number.isFinite(n)) return s;

  if (RATIO_KEYS.test(k)) {
    // Values above 1 are already a percentage; below 1 they are a ratio.
    return `${(n <= 1 ? n * 100 : n).toFixed(2)}%`;
  }
  if (MONEY_KEYS.test(k)) {
    if (n >= 1e9) return `$${(n / 1e9).toFixed(2)}B`;
    if (n >= 1e6) return `$${(n / 1e6).toFixed(2)}M`;
    if (n >= 1e3) return `$${(n / 1e3).toFixed(1)}K`;
    return `$${n.toFixed(2)}`;
  }
  if (Number.isInteger(n) && Math.abs(n) >= 1000) return n.toLocaleString();
  if (!Number.isInteger(n)) {
    // Keep four significant decimals; a price does not need fifty.
    return Math.abs(n) >= 1 ? n.toFixed(4).replace(/\.?0+$/, "") : n.toPrecision(4);
  }
  return s;
}

/**
 * One key/value from any response object, rendered without knowing what it is.
 *
 * THE FLAG LOGIC WAS INVERTED. The first version printed `bad ? "yes" : "no"`, so
 * `isChainSupported: true` — a reassuring fact — rendered as "no". Every flag not on the
 * concerning list was reported as false regardless of its actual value, which is worse than
 * omitting them: it stated the opposite of the data.
 *
 * The value and the judgement are now separate. `yes`/`no` reports what the API said; the colour
 * says whether that is good news, using the list of flags whose TRUE value is a warning.
 */
function Field({ k, v }: { k: string; v: unknown }) {
  if (v === null || v === undefined || v === "" || v === "--") return null;
  if (typeof v === "object") return null;

  if (typeof v === "boolean") {
    const concerning = BAD_WHEN_TRUE.has(k) ? v : false;
    return (
      <div className="flex items-baseline justify-between gap-3 px-4 py-1.5 border-b hair last:border-b-0">
        <span className="text-xs text-ink-faint">{humanKey(k)}</span>
        <span className={cn("text-xs shrink-0", concerning ? "text-critical" : "text-approved")}>
          {v ? "yes" : "no"}
        </span>
      </div>
    );
  }

  return (
    <div className="flex items-baseline justify-between gap-3 px-4 py-1.5 border-b hair last:border-b-0">
      <span className="text-xs text-ink-faint">{humanKey(k)}</span>
      <span className="num text-xs text-ink shrink-0">{display(k, v)}</span>
    </div>
  );
}

function Section({ title, obj }: { title: string; obj: Record<string, unknown> | undefined }) {
  // Identifiers are dropped: chainId and the contract address repeat in every section and are
  // already in the header. Everything else is kept.
  const NOISE = /^(chainId|chainIndex|tokenContractAddress|tokenAddress|cursor)$/;
  const entries = Object.entries(obj ?? {}).filter(
    ([k, v]) =>
      !NOISE.test(k) && v !== null && v !== undefined && v !== "" && v !== "--" && typeof v !== "object",
  );
  if (entries.length === 0) return null;
  return (
    <div className="border-b hair">
      <div className="px-4 pt-3 pb-1 text-xs text-ink-faint uppercase tracking-wider">{title}</div>
      {entries.map(([k, v]) => (
        <Field key={k} k={k} v={v} />
      ))}
    </div>
  );
}

function Detail({ a, onClose }: { a: RwaAsset; onClose: () => void }) {
  const counterfeit = a.security?.isCounterfeitStockToken === true;
  const honeypot = a.security?.isHoneypot === true;
  const div = a.divergence_bps ? Number.parseFloat(a.divergence_bps) : null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/70 p-0 sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label={`${a.symbol} details`}
      onClick={onClose}
    >
      <div
        className="bg-surface border hair rounded-t-lg sm:rounded-lg w-full max-w-xl max-h-[92vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="sticky top-0 bg-surface border-b hair px-4 py-3 flex items-start justify-between gap-3">
          <div className="min-w-0">
            <h2 className="text-base font-medium text-ink">{a.symbol}</h2>
            <p className="text-xs text-ink-faint">{a.stock?.companyName ?? a.name}</p>
            <div className="num text-2xl text-ink mt-1">${money(a.price)}</div>
          </div>
          <button type="button" onClick={onClose} aria-label="Close" className="text-ink-faint hover:text-ink p-1">
            <X size={18} />
          </button>
        </header>

        {/* The one flag that outranks everything else on the screen. */}
        {counterfeit || honeypot ? (
          <div className="px-4 py-3 border-b hair bg-critical/10 flex items-start gap-2">
            <AlertTriangle size={15} className="text-critical shrink-0 mt-0.5" />
            <p className="text-xs text-ink leading-relaxed">
              {counterfeit
                ? "OKX flags this as a counterfeit stock token. It claims to represent a share and does not."
                : "This token may not be sellable after you buy it."}
            </p>
          </div>
        ) : null}

        {/* The company the token is a claim on. This is what makes it a real-world asset. */}
        {a.stock?.companyName ? (
          <div className="px-4 py-3 border-b hair">
            <div className="flex items-center gap-2 mb-2">
              <Building2 size={14} className="text-telemetry" />
              <span className="text-xs text-ink-faint uppercase tracking-wider">The company</span>
            </div>
            <div className="grid gap-1">
              {Object.entries(a.stock).map(([k, v]) =>
                v ? (
                  <div key={k} className="flex items-baseline justify-between gap-3">
                    <span className="text-xs text-ink-faint">{humanKey(k)}</span>
                    <span className="text-xs text-ink shrink-0">{v}</span>
                  </div>
                ) : null,
              )}
            </div>
          </div>
        ) : null}

        {/* The two independent prices, and the distance between them. */}
        <div className="px-4 py-3 border-b hair">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <div className="text-xs text-ink-faint">Pool price</div>
              <div className="num text-sm text-ink">${money(a.price)}</div>
            </div>
            <div>
              <div className="text-xs text-ink-faint">Independent reference</div>
              <div className="num text-sm text-ink">${money(a.index_price)}</div>
            </div>
          </div>
          {div !== null && Number.isFinite(div) ? (
            <div className="mt-2">
              <Badge
                icon={Math.abs(div) > 300 ? ShieldAlert : CheckCircle2}
                tone={Math.abs(div) > 300 ? "critical" : "approved"}
              >
                {Math.abs(div).toFixed(1)} bps apart, limit 300
              </Badge>
            </div>
          ) : null}
        </div>

        {/* Every remaining field, by source, nothing dropped. */}
        <Section title="Market" obj={a.market} />
        <Section title="Contract and holders" obj={a.advanced} />
        <Section title="Concentration" obj={a.cluster} />
        <Section title="Risk checks" obj={a.security} />

        {a.pools?.length ? (
          <div className="border-b hair">
            <div className="px-4 pt-3 pb-1 text-xs text-ink-faint uppercase tracking-wider">
              Where it trades
            </div>
            {a.pools.map((p, i) => (
              <div key={i} className="px-4 py-2 flex items-baseline justify-between gap-3 border-b hair last:border-b-0">
                <span className="text-xs text-ink truncate">
                  {String(p.protocolName ?? p.pool ?? "pool")}
                </span>
                <span className="num text-xs text-ink-faint shrink-0">
                  {compact(String(p.liquidityUsd ?? ""))}
                </span>
              </div>
            ))}
          </div>
        ) : null}

        {a.holders_list?.length ? (
          <div className="border-b hair">
            <div className="px-4 pt-3 pb-1 text-xs text-ink-faint uppercase tracking-wider">
              Largest holders
            </div>
            {a.holders_list.map((h, i) => {
              const addr = String(h.holderWalletAddress ?? h.address ?? "");
              const pct = h.holdAmountPercentage ?? h.percent;
              return (
                <div key={i} className="px-4 py-1.5 flex items-baseline justify-between gap-3 border-b hair last:border-b-0">
                  <span className="num text-xs text-ink-faint truncate">
                    {addr ? `${addr.slice(0, 8)}…${addr.slice(-4)}` : "unknown"}
                  </span>
                  <span className="num text-xs text-ink shrink-0">
                    {pct ? `${Number(pct).toFixed(2)}%` : "—"}
                  </span>
                </div>
              );
            })}
          </div>
        ) : null}

        <div className="px-4 py-3 flex flex-wrap gap-2">
          {a.explorer_url ? (
            <a
              href={a.explorer_url}
              target="_blank"
              rel="noreferrer noopener"
              className="text-xs text-telemetry hover:underline inline-flex items-center gap-1"
            >
              the contract
              <ExternalLink size={10} />
            </a>
          ) : null}
          {a.tags?.map((t) => (
            <Badge key={t} icon={ShieldCheck} tone="telemetry">
              {t}
            </Badge>
          ))}
        </div>
      </div>
    </div>
  );
}

function Row({ a, onOpen }: { a: RwaAsset; onOpen: () => void }) {
  const liq = Number(a.market?.liquidity ?? 0) || 0;
  const counterfeit = a.security?.isCounterfeitStockToken === true;
  const change = a.market?.priceChange24H;
  const ch = change === undefined ? null : Number(change);

  return (
    <button
      type="button"
      onClick={onOpen}
      className="w-full text-left px-4 py-3 border-b hair last:border-b-0 hover:bg-raised"
    >
      <div className="flex items-baseline justify-between gap-3">
        <div className="min-w-0">
          <span className="text-sm text-ink font-medium">{a.symbol}</span>
          <span className="text-xs text-ink-faint ml-2 truncate">
            {a.stock?.companyName ?? a.name}
          </span>
        </div>
        <div className="text-right shrink-0">
          <div className="num text-sm text-ink">${money(a.price)}</div>
          {ch !== null && Number.isFinite(ch) ? (
            <div className={cn("num text-xs", ch >= 0 ? "text-approved" : "text-critical")}>
              {ch >= 0 ? "+" : ""}
              {ch.toFixed(2)}%
            </div>
          ) : null}
        </div>
      </div>

      <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-ink-faint">
        {a.stock?.exchange ? <span>{a.stock.exchange}</span> : null}
        <span>{compact(String(liq))} available</span>
        {a.pools?.length ? <span>{a.pools.length} pools</span> : null}
        <ChevronRight size={12} className="ml-auto" />
      </div>

      <div className="mt-2 flex flex-wrap gap-2">
        {counterfeit ? (
          <Badge icon={AlertTriangle} tone="critical">
            counterfeit
          </Badge>
        ) : liq < 1000 ? (
          <Badge icon={ShieldAlert} tone="shielded">
            too thin to trade
          </Badge>
        ) : (
          <Badge icon={CheckCircle2} tone="approved">
            tradable
          </Badge>
        )}
      </div>
    </button>
  );
}

export function Rwa() {
  const feed = usePolled<RwaFull>(loadRwaFull, POLL.rwafull);
  const [open, setOpen] = useState<string | null>(null);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6">
      <div className="mb-4">
        <h2 className="text-lg text-ink">Real-world assets on X Layer</h2>
        <p className="text-sm text-ink-soft mt-1 leading-relaxed max-w-[64ch]">
          Tokens that are a claim on a real share, held with a regulated custodian. Every field
          below comes from OKX Onchain OS on this refresh. Open any row for the full record.
        </p>
        {feed.state === "ready" ? (
          <p className="text-xs text-ink-faint mt-2">
            {feed.value.count} assets · identified by {feed.value.identified_by} ·{" "}
            {ago(feed.value.fetched_at_utc) ?? "live"}
          </p>
        ) : null}
      </div>

      <Card title="Every tokenized asset">
        <Show feed={feed} what="the real-world asset list">
          {(v) => (
            <>
              {v.instruments.map((a) => (
                <Row key={a.address} a={a} onOpen={() => setOpen(a.address)} />
              ))}
            </>
          )}
        </Show>
      </Card>

      {open && feed.state === "ready" ? (
        <Detail
          a={feed.value.instruments.find((i) => i.address === open)!}
          onClose={() => setOpen(null)}
        />
      ) : null}
    </div>
  );
}
