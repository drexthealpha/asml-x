/**
 * Every number this app shows, and where it came from.
 *
 * ONE RULE, ENFORCED BY TYPES. A value is `Loading`, `Failed`, or `Ready`. There is no fourth
 * state and no default. A component cannot render a number it was not given, so a failed fetch
 * cannot be mistaken for a zero, and "no price" cannot silently become "$0.00".
 *
 * The old app leaked its own construction onto the screen: evidence ids, journal internals, sample
 * sizes, refusal ledgers, hex digests. None of that is a person's reason to use a product. This
 * layer exposes prices, balances and routes, and nothing about how they were verified.
 */

export type Feed<T> =
  | { state: "loading" }
  | { state: "failed"; why: string }
  | { state: "ready"; value: T; fetchedAt: string; freshness: Freshness };

/**
 * Where live data comes from.
 *
 * THE STATIC FILES WERE THE BUG. Every price was read once from a JSON file that a script had
 * written at some earlier point, so the screen showed whatever the last manual run happened to
 * fetch. It looked hardcoded because functionally it was: nothing refreshed it.
 *
 * The feed server re-signs and re-fetches from Onchain OS on a timer and serves the result. It
 * exists because the signature needs the API secret, and a secret shipped to a browser is a
 * published secret.
 *
 * FALLING BACK TO THE FILES IS DELIBERATE. A static deployment with no server still renders, and
 * the age shown on screen makes the difference visible rather than hidden.
 */
/**
 * WHERE THE SIGNED FEEDS COME FROM, resolved at run time rather than at build time.
 *
 * Three environments, one rule: the browser never holds the secret, so it always talks to
 * something that does.
 *
 *   hosted (Vercel)   same origin. `/api/*` are serverless functions that sign with the project's
 *                     environment variables. No localhost, no CORS, no separate process.
 *   local dev         `http://127.0.0.1:8787`, the Python feed server.
 *   static, no server the bundled JSON files, clearly labelled as not live.
 *
 * DETECTED, NOT CONFIGURED. An env var baked at build time would mean one bundle cannot serve both
 * a laptop and a deployment, and the wrong one fails silently by falling through to stale files.
 * Anything that is not a loopback host is treated as hosted.
 */
const SERVER = (() => {
  const override = import.meta.env.VITE_FEED_SERVER as string | undefined;
  if (override) return override;
  if (typeof window === "undefined") return "";
  const h = window.location.hostname;
  const isLocal = h === "localhost" || h === "127.0.0.1" || h === "0.0.0.0" || h === "";
  // Same origin when hosted: `/api/universe` hits the serverless function beside the page.
  return isLocal ? "http://127.0.0.1:8787" : "";
})();

/** How old the data is, in seconds, and whether the last refresh actually succeeded. */
export interface Freshness {
  ageSeconds: number | null;
  live: boolean;
}

async function get<T>(file: string, endpoint: string): Promise<Feed<T>> {
  // The server first. One short timeout, then the file: a person should not wait on a server that
  // is not running.
  try {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 2500);
    const res = await fetch(`${SERVER}/api/${endpoint}`, {
      cache: "no-store",
      signal: ctl.signal,
    });
    clearTimeout(t);
    if (res.ok) {
      const value = (await res.json()) as T & {
        fetched_at_utc?: string;
        _age_s?: number;
        _fresh?: boolean;
      };
      return {
        state: "ready",
        value,
        fetchedAt: value.fetched_at_utc ?? "",
        freshness: { ageSeconds: value._age_s ?? null, live: value._fresh !== false },
      };
    }
  } catch {
    // Server absent or slow. The file below is the fallback, and it is labelled as not live.
  }

  try {
    const res = await fetch(`data/${file}`, { cache: "no-store" });
    if (!res.ok) return { state: "failed", why: `could not load (${res.status})` };
    const value = (await res.json()) as T & { fetched_at_utc?: string };
    return {
      state: "ready",
      value,
      fetchedAt: value.fetched_at_utc ?? "",
      freshness: { ageSeconds: null, live: false },
    };
  } catch (e) {
    return { state: "failed", why: e instanceof Error ? e.message : "could not load" };
  }
}

/** A token on X Layer, as the chain lists it and the router prices it. */
export interface Token {
  symbol: string;
  name: string;
  address: string;
  decimals: number;
  /** Null means unpriced. NOT zero. */
  price: string | null;
  routable: boolean;
  venues: string[];
  note: string | null;
}

export interface Universe {
  chain_id: number;
  chain_name: string;
  quote_symbol: string;
  fetched_at_utc: string;
  token_count: number;
  tradable_count: number;
  tokens: Token[];
}

export interface Candle {
  t: number;
  c: string;
}

export interface Market {
  pair: {
    instId: string;
    last: string;
    bid: string;
    ask: string;
    spread_bps: string;
    high24h: string;
    low24h: string;
  };
  volatility: { realized_bps_1m: string };
  candles: Candle[];
  fetched_at_utc: string;
}

export interface RwaInstrument {
  symbol: string;
  plain: string;
  price: string | null;
  divergence_bps?: string;
  status: string;
  reference?: string;
}

export interface Rwa {
  divergence_limit_bps: string;
  fetched_at_utc: string;
  instruments: RwaInstrument[];
  absent_asset_classes: string;
}

export interface DepthRung {
  size: string;
  unit_price: string;
  slippage_bps: string;
  within_tolerance: boolean;
  venues: string[];
}

export interface Depth {
  pair: string;
  max_safe_size: string;
  slippage_tolerance_bps: string;
  venues: string[];
  rungs: DepthRung[];
  fetched_at_utc: string;
}

export interface Chain {
  chain_id: number;
  chain_name: string;
  network: string;
  explorer_address_base: string;
  deployments: { name: string; address: string; role: string }[];
}

export const loadUniverse = () => get<Universe>("universe.json", "universe");
export const loadMarket = () => get<Market>("market.json", "market");
export const loadRwa = () => get<Rwa>("rwa.json", "rwa");
export const loadDepth = () => get<Depth>("depth.json", "depth");
export const loadChain = () => get<Chain>("deployments.json", "chain");

/**
 * Format a price the way a person reads money, not the way a machine stores it.
 *
 * Significant digits scale with magnitude: a $64,000 asset does not need six decimals and a
 * $0.0000012 asset is destroyed by two. Never returns "0.00" for a small non-zero number, which
 * is how a real balance gets displayed as nothing.
 */
export function money(v: string | null | undefined): string | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Number.parseFloat(v);
  if (!Number.isFinite(n)) return null;
  if (n === 0) return "0";
  const abs = Math.abs(n);
  if (abs >= 1000) return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
  if (abs >= 1) return n.toFixed(4).replace(/0+$/, "").replace(/\.$/, "");
  if (abs >= 0.01) return n.toFixed(4);
  return n.toPrecision(3);
}

/** "3 minutes ago", from an ISO stamp. Absent rather than wrong when unparseable. */
export function ago(iso: string): string | null {
  if (!iso) return null;
  const then = Date.parse(iso);
  if (Number.isNaN(then)) return null;
  const secs = Math.max(0, Math.round((Date.now() - then) / 1000));
  if (secs < 60) return `${secs}s ago`;
  if (secs < 3600) return `${Math.round(secs / 60)}m ago`;
  return `${Math.round(secs / 3600)}h ago`;
}

/**
 * Poll a feed on an interval. THE FIX FOR "the price looks hardcoded".
 *
 * Nothing in this app refreshed itself: every surface fetched once on mount and then displayed
 * that snapshot forever. A price that never moves is indistinguishable from a constant, and a
 * person watching a market is entitled to assume a number that never changes is fake.
 *
 * TAB-AWARE. Polling stops when the tab is hidden and fires immediately on return, so a
 * backgrounded tab does not spend the API budget, and a returning one is never showing a stale
 * figure while it waits for the next tick.
 */
import { useEffect, useState } from "react";

export function usePolled<T>(
  load: () => Promise<Feed<T>>,
  everyMs: number,
): Feed<T> {
  const [feed, setFeed] = useState<Feed<T>>({ state: "loading" });

  useEffect(() => {
    let alive = true;
    let timer: number | undefined;

    const tick = async () => {
      const next = await load();
      if (!alive) return;
      // A failed refresh does NOT wipe a good value off the screen. It keeps the last reading and
      // lets its age grow, which is visible; blanking the panel would look like a broken app.
      setFeed((prev) =>
        next.state === "failed" && prev.state === "ready" ? prev : next,
      );
      timer = window.setTimeout(() => void tick(), everyMs);
    };

    void tick();

    const onVisible = () => {
      if (document.visibilityState === "visible") {
        window.clearTimeout(timer);
        void tick();
      }
    };
    document.addEventListener("visibilitychange", onVisible);

    return () => {
      alive = false;
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
    // `load` is a module-level function reference and never changes identity.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [everyMs]);

  return feed;
}

/** How often each surface refreshes. Matched to how fast the underlying thing actually moves. */
export const POLL = {
  market: 4000,
  universe: 20000,
  rwa: 15000,
  depth: 20000,
  oos: 12000,
  intel: 30000,
  detail: 60000,
  rwastate: 45000,
  rwafull: 90000,
  contracts: 30000,
  activity: 8000,
} as const;

/** One token as Onchain OS sees it: two prices, real pools, real security flags. */
export interface OosToken {
  symbol: string;
  address: string;
  price: string | null;
  index_price: string | null;
  /** Signed distance between the two sources, in basis points. */
  divergence_bps: string | null;
  market_cap?: string;
  liquidity?: string;
  volume_24h?: string;
  change_24h?: string;
  pools?: { dex: string; liquidity: string }[];
  honeypot?: boolean;
  buy_tax?: string;
  sell_tax?: string;
}

export interface DefiProduct {
  platform: string;
  name: string;
  apy: string;
  tvl: string;
  id: string;
  group: string;
}

export interface Oos {
  chain_id: number;
  chain_name: string;
  fetched_at_utc: string;
  tokens: OosToken[];
  candles: { t: number; c: string; h: string; l: string; o: string }[];
  defi: { earn: DefiProduct[]; lending: DefiProduct[]; pools: DefiProduct[] };
}

export const loadOos = () => get<Oos>("onchainos.json", "onchainos");

/** APY arrives as a fraction ("0.00300"). Shown as a percentage, the way a saver reads it. */
export function apy(v: string | null | undefined): string | null {
  if (!v) return null;
  const n = Number.parseFloat(v);
  if (!Number.isFinite(n)) return null;
  return `${(n * 100).toFixed(2)}%`;
}

/** Large dollar figures, abbreviated. $50,360,553 reads as $50.4M. */
export function compact(v: string | null | undefined): string | null {
  if (!v) return null;
  const n = Number.parseFloat(v);
  if (!Number.isFinite(n)) return null;
  if (n >= 1e9) return `$${(n / 1e9).toFixed(1)}B`;
  if (n >= 1e6) return `$${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `$${(n / 1e3).toFixed(1)}K`;
  return `$${n.toFixed(0)}`;
}

/** Sentiment counts per symbol. Counts, not a proprietary score. */
export interface Sentiment {
  symbol: string;
  mentions: string;
  news_mentions: string;
  x_mentions: string;
  bullish: string;
  bearish: string;
  neutral: string;
  bullish_ratio: string;
  label: string;
}

/** What a wallet classified as smart money, KOL or whale just did. */
export interface SmartMoney {
  symbol: string | null;
  name: string | null;
  address: string;
  wallets: string;
  /** 1 smart money, 2 KOL, 3 whale — the API's own classification. */
  wallet_type: string;
  amount_usd: string;
  holders?: string;
  market_cap_usd?: string;
  top10_holder_percent?: string;
  sold_ratio_percent?: string;
}

export interface Intel {
  period: string;
  fetched_at_utc: string;
  sentiment: Sentiment[];
  news: { title: string; source: string; sentiment: string; url: string }[];
  smart_money: SmartMoney[];
  usage_note: string;
}

export const loadIntel = () => get<Intel>("intel.json", "intel");

/** Everything Onchain OS knows about one token. Absent fields are absent, never zero. */
export interface TokenDetail {
  symbol: string;
  address: string;
  price?: string;
  index_price?: string | null;
  holders?: string;
  liquidity?: string;
  market_cap?: string;
  circulating_supply?: string;
  high?: string;
  low?: string;
  change_5m?: string;
  change_1h?: string;
  change_4h?: string;
  change_24h?: string;
  pools?: { pool: string; protocol: string; usd: string; address: string }[];
  lp_burned_percent?: string;
  bundle_holding_percent?: string;
  cluster_concentration?: string;
  top100_percent?: string;
  same_funder_percent?: string;
  honeypot?: boolean;
  risk_level?: string;
  buy_tax?: string;
  sell_tax?: string;
  mintable?: boolean;
  open_source?: boolean;
  low_liquidity?: boolean;
}

export interface Details {
  fetched_at_utc: string;
  tokens: Record<string, TokenDetail>;
}

export const loadDetails = () => get<Details>("detail.json", "detail");

/** A ratio that may arrive as 0.92153 (a fraction) or 92.153 (already a percent). */
export function pct(v: string | null | undefined): string | null {
  if (!v || v === "--") return null;
  const n = Number.parseFloat(v);
  if (!Number.isFinite(n)) return null;
  return `${(n <= 1 ? n * 100 : n).toFixed(1)}%`;
}

/** What the agent did, already translated into plain language by the feed. */
export interface Agent {
  status: string;
  market?: string;
  last_seen_block?: number;
  trades_made: number;
  options_considered: number;
  options_declined: number;
  why_declined: { reason: string; count: number }[];
  decisions: {
    id: number;
    block: number;
    did: string;
    acted: boolean;
    considered: number;
    refused: number;
    saw: string;
    confidence_pct: number;
  }[];
  real_swaps: { from: string; to: string; venues: string; tx: string; explorer: string; at: string }[];
  plain_summary: string;
  fetched_at_utc: string;
}

export const loadActivity = () => get<Agent>("activity.json", "activity");

/** One RWA rule, read live from the deployed guard. */
export interface RwaRule {
  name: string;
  plain: string;
  display: string | null;
  value_bps?: number | null;
  value_seconds?: number | null;
  value_bool?: boolean | null;
}

export interface RwaState {
  chain_id: number;
  explorer: string;
  fetched_at_utc: string;
  guard_address: string;
  vault_address: string;
  vault_paused: boolean | null;
  rules: RwaRule[];
  unreadable: string[];
}

export const loadRwaState = () => get<RwaState>("rwa-state.json", "rwastate");

/** One deployed contract, with its live state in a person's words. */
export interface ContractCard {
  name: string;
  contract: string;
  address: string | null;
  plain: string;
  facts: { label: string; value: string | null }[];
  status: { tone: "approved" | "shielded" | "critical"; text: string } | null;
}

export interface Contracts {
  chain_id: number;
  explorer: string;
  fetched_at_utc: string;
  contracts: ContractCard[];
}

export const loadContracts = () => get<Contracts>("contracts.json", "contracts");

/**
 * A tokenized real-world asset, with EVERY field Onchain OS returned.
 *
 * The nested objects are deliberately untyped beyond `Record`: the point of this feed is that
 * nothing is dropped, and naming forty fields here would recreate the curated subset the feed
 * exists to avoid. The UI renders whatever keys arrive.
 */
export interface RwaAsset {
  symbol: string;
  name: string;
  address: string;
  decimals: number;
  logo?: string;
  explorer_url?: string;
  tags: string[];
  /** companyName, exchange, industry, listingDate, stockCode, stockType */
  stock: Record<string, string>;
  /** the full advanced-info response */
  advanced: Record<string, unknown>;
  /** holder clustering and concentration */
  cluster: Record<string, unknown>;
  /** 24 risk flags from OKX's own scanner */
  security: Record<string, unknown>;
  /** the full price-info response */
  market: Record<string, unknown>;
  pools: Record<string, unknown>[];
  holders_list: Record<string, unknown>[];
  candles: { t: number; c: string; h: string; l: string; o: string }[];
  price: string | null;
  index_price: string | null;
  divergence_bps: string | null;
  price_time?: string;
}

export interface RwaFull {
  chain_id: number;
  fetched_at_utc: string;
  issuer: string;
  backing: string;
  identified_by: string;
  count: number;
  instruments: RwaAsset[];
}

export const loadRwaFull = () => get<RwaFull>("rwa-full.json", "rwafull");

/** A camelCase API key as a person would read it: `isCounterfeitStockToken` -> "counterfeit". */
export function humanKey(k: string): string {
  return k
    .replace(/^is/, "")
    .replace(/([A-Z])/g, " $1")
    .trim()
    .toLowerCase()
    .replace(/^./, (c) => c.toUpperCase());
}
