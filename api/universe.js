/**
 * Every token on X Layer, priced and route-checked. The hosted equivalent of `okx_universe.py`.
 *
 * WHY IT MIRRORS THE PYTHON RATHER THAN SIMPLIFYING IT. The local feed and the hosted one must
 * produce the same shape, or the UI behaves differently depending on where it is served from and
 * every bug becomes "which environment". So this returns the same fields, with the same absence
 * rules: a token with no price is `null`, never zero, and one the router declines carries the
 * router's own words.
 */

import { CHAIN, get, post, requireCreds, send } from "./_okx.js";

export default async function handler(req, res) {
  const c = requireCreds(res);
  if (!c) return;

  const listed = await get(`/api/v6/dex/aggregator/all-tokens?chainIndex=${CHAIN}`, c);
  if (!listed) return send(res, 502, { error: "could not read the chain token list" });

  // Addresses are DISCOVERED here too. Not one is written into this file.
  const tokens = [];
  const seen = new Set();
  for (const t of listed) {
    const sym = (t.tokenSymbol || "").trim();
    if (!sym || seen.has(sym) || !t.tokenContractAddress) continue;
    seen.add(sym);
    tokens.push({
      symbol: sym,
      name: (t.tokenName || "").trim(),
      address: t.tokenContractAddress,
      decimals: Number(t.decimals ?? 18),
    });
  }

  const quoteSymbol = "USDT";
  const quote = tokens.find((t) => t.symbol === quoteSymbol);
  if (!quote) return send(res, 502, { error: `chain ${CHAIN} does not list ${quoteSymbol}` });

  // Prices in batches, the same 20 at a time the local feed uses.
  const prices = new Map();
  for (let i = 0; i < tokens.length; i += 20) {
    const body = tokens
      .slice(i, i + 20)
      .map((t) => ({ chainIndex: CHAIN, tokenContractAddress: t.address }));
    const rows = await post("/api/v6/dex/market/price", body, c);
    for (const r of rows || []) {
      if (r.price) prices.set(r.tokenContractAddress.toLowerCase(), r.price);
    }
  }

  // Routability, one real quote per token, in parallel. A serverless function has a wall clock,
  // so these run concurrently rather than in the sequential loop the local script can afford.
  const rows = await Promise.all(
    tokens.map(async (t) => {
      const price = prices.get(t.address.toLowerCase()) ?? null;
      if (t.address.toLowerCase() === quote.address.toLowerCase()) {
        return { ...t, price, routable: true, venues: [], note: "this is the quote asset" };
      }
      const one = 10n ** BigInt(t.decimals);
      const q = await get(
        `/api/v6/dex/aggregator/quote?chainIndex=${CHAIN}&amount=${one}` +
          `&fromTokenAddress=${t.address}&toTokenAddress=${quote.address}`,
        c,
      );
      const venues = [];
      for (const hop of q?.[0]?.dexRouterList || []) {
        const n = hop?.dexProtocol?.dexName;
        if (n && !venues.includes(n)) venues.push(n);
      }
      return {
        ...t,
        price,
        routable: Boolean(q?.length),
        venues,
        note: q?.length ? null : "the router did not return a route",
      };
    }),
  );

  send(res, 200, {
    source: "OKX Onchain OS, signed in a Vercel function",
    chain_id: Number(CHAIN),
    chain_name: "X Layer",
    quote_symbol: quoteSymbol,
    fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    token_count: rows.length,
    tradable_count: rows.filter((r) => r.routable && r.price).length,
    tokens: rows,
  });
}
