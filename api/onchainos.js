/**
 * Real-world assets with TWO independent prices, plus live DeFi yield.
 *
 * REWRITTEN AGAINST VERIFIED PATHS. The first version called `market/price` and `market/price-info`
 * as GETs and invented an index-price path. All three returned nothing, every field became null,
 * and the deployed site showed "no price" for eighteen tokens that all have one. Nothing errored:
 * the signed helper returns null on a bad path, and null renders as absence. A dead client looked
 * exactly like a dead market.
 *
 * Every path now comes from `_paths.js`, and nothing goes in there until
 * `scripts/232-verify-rest-paths.sh` has printed it beside real data.
 *
 * THE TWO PRICES ARE THE POINT. `price` is derived from the pools; `index` is aggregated across
 * sources. They are separate measurements, so the distance between them means something. With only
 * one, the RWA divergence check compares a price to itself: always zero, always passing.
 */

import { CHAIN, get, post, requireCreds, send } from "./_okx.js";
import { PATHS, batch } from "./_paths.js";

/** Symbols only. Every address is resolved from the chain's own listing on each request. */
const FOCUS = ["WOKB", "USDT", "USDC", "ETH", "WBTC", "xBTC", "DAI", "USDG"];

/** Batch POST helper: one call for many tokens, keyed by lowercase address. */
async function priceMap(pathFn, addresses, c) {
  const { path } = pathFn();
  const rows = await post(path, batch(CHAIN, addresses), c);
  const m = new Map();
  for (const r of rows || []) {
    if (r?.tokenContractAddress) m.set(r.tokenContractAddress.toLowerCase(), r);
  }
  return m;
}

async function defi(group, tokens, c) {
  const { path } = PATHS.defiSearch();
  const raw = await post(
    path,
    { chainIndex: CHAIN, productGroup: group, tokenKeywords: tokens },
    c,
  );
  return (raw?.list || []).map((p) => ({
    platform: p.platformName,
    name: p.name || p.investmentName || p.platformName,
    apy: p.rate,
    tvl: p.tvl,
    id: String(p.investmentId ?? ""),
    group,
  }));
}

export default async function handler(req, res) {
  const c = requireCreds(res);
  if (!c) return;

  const listed = await get(PATHS.allTokens(CHAIN).path, c);
  if (!listed) return send(res, 502, { error: "could not read the chain token list" });

  const bySymbol = new Map();
  for (const t of listed) {
    const s = (t.tokenSymbol || "").trim();
    if (s && !bySymbol.has(s)) bySymbol.set(s, t);
  }

  const picked = FOCUS.filter((s) => bySymbol.has(s)).map((s) => ({
    symbol: s,
    address: bySymbol.get(s).tokenContractAddress,
    name: (bySymbol.get(s).tokenName || "").trim(),
  }));
  const addresses = picked.map((p) => p.address);

  // THREE BATCH CALLS, not eight tokens times three. A serverless function has a wall clock, and
  // per-token fan-out is what made the universe endpoint return 4 routable instead of 16.
  const [prices, indexes, infos] = await Promise.all([
    priceMap(PATHS.price, addresses, c),
    priceMap(PATHS.indexPrice, addresses, c),
    priceMap(PATHS.priceInfo, addresses, c),
  ]);

  const tokens = picked.map((p) => {
    const k = p.address.toLowerCase();
    const price = prices.get(k)?.price ?? null;
    const index = indexes.get(k)?.price ?? null;
    const info = infos.get(k) || {};

    let divergence = null;
    if (price && index && Number(index) !== 0) {
      divergence = (((Number(price) - Number(index)) / Number(index)) * 10000).toFixed(2);
    }

    return {
      symbol: p.symbol,
      address: p.address,
      price,
      index_price: index,
      divergence_bps: divergence,
      market_cap: info.marketCap ?? null,
      liquidity: info.liquidity ?? null,
      volume_24h: info.volume24H ?? null,
      change_24h: info.priceChange24H ?? null,
      holders: info.holders ?? null,
      pools: [],
    };
  });

  const [earn, lending] = await Promise.all([
    defi("SINGLE_EARN", ["USDT", "USDC", "OKB"], c),
    defi("LENDING", ["USDT", "USDC"], c),
  ]);

  send(res, 200, {
    source: "OKX Onchain OS, signed in a Vercel function, verified paths",
    chain_id: Number(CHAIN),
    chain_name: "X Layer",
    fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    tokens,
    // Stated so a consumer can tell a broken client from an empty market, which is the exact
    // confusion the first version created.
    priced_count: tokens.filter((t) => t.price).length,
    candles: [],
    defi: { earn, lending, pools: [] },
  });
}
