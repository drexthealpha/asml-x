/**
 * Tokenized equities on X Layer. The real-world assets I twice said were not there.
 *
 * I CHECKED ONE SURFACE AND REPORTED A CONCLUSION ABOUT THE CHAIN. `aggregator/all-tokens` returns
 * 22 tokens for chain 196 and none of them is an equity, so I said X Layer has no tokenized stocks.
 * The token SEARCH endpoint covers a far larger universe and was never queried. It has eighteen
 * xStocks, and seven of them carry real liquidity:
 *
 *   TSLAx  $720k    NVDAx  $518k    GOOGLx $479k    QQQx  $394k
 *   AAPLx  $303k    METAx  $285k    MSFTx  $274k    GLDx  $947 (too thin)
 *
 * Backed Finance issues these 1:1 against the real share, held with a regulated custodian under
 * Swiss DLT law. TSLAx is a claim on a Tesla share, not a token named after one. That is the exact
 * instrument class the RWA guard was written for: an external reference to track, an issuer who can
 * halt, a redemption mechanism, an oracle that can go stale.
 *
 * "Absent from the list I checked" is not "absent from the chain", and stating the second having
 * established only the first is the same failure as inventing a feature, in the other direction.
 *
 * THIN ONES ARE SHOWN AND MARKED, NOT HIDDEN. A token called TSLAx with $19 of liquidity is more
 * dangerous than showing nothing, because the name lends it credibility the market does not. Each
 * instrument carries `tradable` with the reason it failed.
 */

import { CHAIN, get, post, requireCreds, send } from "./_okx.js";
import { PATHS, batch } from "./_paths.js";

/** QUERIES, not a token list. Symbols and addresses are discovered, never written here. */
const QUERIES = ["xStock", "nasdaq", "tesla", "apple", "nvidia", "gold", "index"];

/** Liquidity below this is not a market. Stated once, applied everywhere. */
const MIN_LIQUIDITY_USD = 1000;

async function search(query, c) {
  // VERIFIED PATH AND PARAMETERS, read out of cli/src/commands/token.rs rather than guessed again.
  //
  // The endpoint is market/token/search, and the parameters are "chains" and "search". Four other
  // spellings (chainIndex/keyword, chainIndexs/keyword, chainIds/query, chainIndexs/query) all
  // returned code 50014 with an empty list, which a caller reads as "no equities on this chain"
  // while the chain has eighteen. An endpoint that answers "nothing" to a malformed query is the
  // most expensive kind of wrong.
  const rows = await get(PATHS.tokenSearch(CHAIN, query).path, c);
  return Array.isArray(rows) ? rows : [];
}

export default async function handler(req, res) {
  const c = requireCreds(res);
  if (!c) return;

  // Discover by search, deduplicated by address.
  const found = new Map();
  const results = await Promise.all(QUERIES.map((q) => search(q, c)));
  for (const rows of results) {
    for (const t of rows) {
      const idx = String(t.chainIndex ?? t.chainId ?? "");
      if (idx && idx !== CHAIN) continue;
      const name = (t.tokenName || "").trim();
      const addr = t.tokenContractAddress;
      const sym = (t.tokenSymbol || "").trim();
      // The issuer's naming is the marker: every one of these ends in "xStock".
      if (!addr || !sym || !name.toLowerCase().includes("xstock")) continue;
      found.set(addr.toLowerCase(), { symbol: sym, name, address: addr });
    }
  }

  const list = [...found.values()].sort((a, b) => a.symbol.localeCompare(b.symbol));
  if (list.length === 0) {
    return send(res, 200, {
      source: "OKX Onchain OS token search",
      chain_id: Number(CHAIN),
      fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
      total_found: 0,
      tradable_count: 0,
      instruments: [],
      note: "The search returned no xStocks on this refresh. Nothing is shown rather than a stale list.",
    });
  }

  const addresses = list.map((t) => t.address);
  const [priceRows, indexRows, infoRows] = await Promise.all([
    post(PATHS.price().path, batch(CHAIN, addresses), c),
    post(PATHS.indexPrice().path, batch(CHAIN, addresses), c),
    post(PATHS.priceInfo().path, batch(CHAIN, addresses), c),
  ]);

  const asMap = (rows) => {
    const m = new Map();
    for (const r of rows || []) {
      if (r?.tokenContractAddress) m.set(r.tokenContractAddress.toLowerCase(), r);
    }
    return m;
  };
  const prices = asMap(priceRows);
  const indexes = asMap(indexRows);
  const infos = asMap(infoRows);

  const instruments = list.map((t) => {
    const k = t.address.toLowerCase();
    const price = prices.get(k)?.price ?? null;
    const index = indexes.get(k)?.price ?? null;
    const info = infos.get(k) || {};
    const liquidity = Number(info.liquidity ?? 0) || 0;

    let divergence = null;
    if (price && index && Number(index) !== 0) {
      divergence = (((Number(price) - Number(index)) / Number(index)) * 10000).toFixed(2);
    }

    const hasPrice = price !== null;
    const hasLiquidity = liquidity >= MIN_LIQUIDITY_USD;
    return {
      ...t,
      // "Apple xStock" -> "Apple", so the row reads as the company it is a claim on.
      company: t.name.replace(/\s*xStock\s*$/i, ""),
      price,
      index_price: index,
      divergence_bps: divergence,
      liquidity_usd: liquidity,
      market_cap: info.marketCap ?? null,
      holders: info.holders ?? null,
      change_24h: info.priceChange24H ?? null,
      has_price: hasPrice,
      has_liquidity: hasLiquidity,
      tradable: hasPrice && hasLiquidity,
      // The reason, so a greyed-out row explains itself instead of just being greyed out.
      blocked_because: hasPrice
        ? hasLiquidity
          ? null
          : "too little liquidity to trade safely"
        : "no price available",
    };
  });

  send(res, 200, {
    source: "OKX Onchain OS token search plus batch price, index and info",
    chain_id: Number(CHAIN),
    chain_name: "X Layer",
    fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    issuer: "Backed Finance",
    backing:
      "Each xStock is issued one-for-one against the real share, held with a regulated custodian " +
      "under Swiss DLT law. The token is a claim on the share, not a token named after it.",
    total_found: instruments.length,
    tradable_count: instruments.filter((i) => i.tradable).length,
    min_liquidity_usd: MIN_LIQUIDITY_USD,
    instruments,
  });
}
