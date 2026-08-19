/**
 * Every token on X Layer, priced and route-checked.
 *
 * WHY THIS WAS REWRITTEN. The first version fired one quote per token, twenty-two of them, inside a
 * single serverless invocation. Vercel's Hobby functions have a ten second wall clock, so most of
 * those calls were cut off and the endpoint reported four routable tokens where the local feed
 * finds sixteen. Nothing errored. The page rendered "cannot trade" against tokens that trade fine.
 *
 * TWO CHANGES:
 *   1. Prices come from ONE batch POST for all tokens, not one call each.
 *   2. Routability is checked for a BOUNDED set, and every other token is marked `unchecked`
 *      rather than `not routable`. Those are different claims and only one of them was measured.
 *
 * That distinction is the point. Saying "we did not check" is honest; saying "cannot trade" about
 * a token nobody looked at is a false statement about someone's money.
 */

import { CHAIN, get, post, requireCreds, send } from "./_okx.js";
import { PATHS, batch } from "./_paths.js";

/** How many tokens get a live route check per invocation, inside the function's time budget. */
const ROUTE_CHECK_LIMIT = 10;

export default async function handler(req, res) {
  const c = requireCreds(res);
  if (!c) return;

  const listed = await get(PATHS.allTokens(CHAIN).path, c);
  if (!listed) return send(res, 502, { error: "could not read the chain token list" });

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

  const quote = tokens.find((t) => t.symbol === "USDT");
  if (!quote) return send(res, 502, { error: `chain ${CHAIN} does not list USDT` });

  // ONE batch call for every price.
  const { path: pricePath } = PATHS.price();
  const priceRows = await post(pricePath, batch(CHAIN, tokens.map((t) => t.address)), c);
  const prices = new Map();
  for (const r of priceRows || []) {
    if (r?.price) prices.set(r.tokenContractAddress.toLowerCase(), r.price);
  }

  // Route checks for the most liquid subset only, so the function finishes. Tokens with a price
  // are checked first: an unpriced token is not tradable regardless of routing.
  const ordered = [...tokens].sort((a, b) => {
    const ap = prices.has(a.address.toLowerCase()) ? 0 : 1;
    const bp = prices.has(b.address.toLowerCase()) ? 0 : 1;
    return ap - bp;
  });
  const toCheck = new Set(ordered.slice(0, ROUTE_CHECK_LIMIT).map((t) => t.address));

  const rows = await Promise.all(
    tokens.map(async (t) => {
      const price = prices.get(t.address.toLowerCase()) ?? null;

      if (t.address.toLowerCase() === quote.address.toLowerCase()) {
        return { ...t, price, routable: true, checked: true, venues: [], note: "this is the quote asset" };
      }
      if (!toCheck.has(t.address)) {
        // NOT the same as "cannot trade". Nobody looked.
        return { ...t, price, routable: null, checked: false, venues: [], note: null };
      }

      const one = 10n ** BigInt(t.decimals);
      const q = await get(
        PATHS.quote(CHAIN, t.address, quote.address, one.toString()).path,
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
        checked: true,
        venues,
        note: q?.length ? null : "the router did not return a route",
      };
    }),
  );

  send(res, 200, {
    source: "OKX Onchain OS, signed in a Vercel function, verified paths",
    chain_id: Number(CHAIN),
    chain_name: "X Layer",
    quote_symbol: "USDT",
    fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    token_count: rows.length,
    priced_count: rows.filter((r) => r.price).length,
    // Only tokens actually checked can be counted as tradable.
    tradable_count: rows.filter((r) => r.routable === true && r.price).length,
    route_checked: rows.filter((r) => r.checked).length,
    tokens: rows,
  });
}
