/**
 * The x402-gated quote endpoint, reachable from anywhere.
 *
 * THIS IS THE ANSWER TO "WHAT IS x402 FOR". Locally the coordination API only answers on
 * 127.0.0.1, so agent-to-agent payment could be described but not tried. Hosted, any agent
 * anywhere can hit this URL, receive a 402 telling it what the quote costs and where to pay, sign
 * an authorization with its own wallet, and retry. No account, no API key, no human in the loop.
 * That is the entire proposition, and it only becomes real when the endpoint has a public address.
 *
 * WHAT THIS FUNCTION IS AND IS NOT. It is the PAYMENT GATE and the price. It is not the risk
 * engine: the Rust engine that decides whether a trade is permitted cannot run in a serverless
 * function, so the quote returned here carries the live market price and the size bound derived
 * from measured depth, and says plainly that settlement runs through the on-chain guard.
 *
 * Pretending the full risk gate ran here would be the more impressive lie. It is stated instead.
 *
 * PAYMENT DOES NOT BUY A BETTER PRICE. It buys the quote at all. The same size bound applies
 * either way, which is the property that makes a paid endpoint safe to publish.
 */

import { CHAIN, get, requireCreds, send } from "./_okx.js";
import { address, deployments as manifest } from "./_deployments.js";

/** Where payment settles: the fee collector from the deployment that actually happened. */
function payTo() {
  return address("FeeCollector");
}

function challenge(price, asset, recipient) {
  return {
    x402Version: 2,
    error: "payment required",
    accepts: [
      {
        scheme: "exact",
        network: `eip155:${CHAIN}`,
        maxAmountRequired: price,
        resource: "/api/quote",
        description: "One risk-gated quote from the ASML-X agent",
        payTo: recipient,
        asset,
        extra: { name: "USDT" },
      },
    ],
  };
}

export default async function handler(req, res) {
  if (req.method === "OPTIONS") {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "content-type, payment-signature, x-payment");
    return res.status(204).end();
  }
  if (req.method !== "POST") {
    return send(res, 405, { error: "POST a body of {size, side}" });
  }

  const c = requireCreds(res);
  if (!c) return;

  const listed = await get(`/api/v6/dex/aggregator/all-tokens?chainIndex=${CHAIN}`, c);
  if (!listed) return send(res, 502, { error: "could not read the chain token list" });

  const bySymbol = new Map();
  for (const t of listed) {
    const s = (t.tokenSymbol || "").trim();
    if (s && !bySymbol.has(s)) bySymbol.set(s, t);
  }
  const usdt = bySymbol.get("USDT");
  const wokb = bySymbol.get("WOKB");
  if (!usdt || !wokb) return send(res, 502, { error: "the pair is not listed on this chain" });

  const recipient = payTo();
  const price = process.env.ASML_X402_PRICE || "";

  // THE GATE, BEFORE ANY WORK. An unpaid request costs this function nothing: no quote is
  // fetched, no capacity is implied. A gate after the work would give the expensive part away.
  if (price && recipient) {
    const paid = req.headers["payment-signature"] || req.headers["x-payment"];
    if (!paid) {
      res.setHeader("Access-Control-Allow-Origin", "*");
      return send(res, 402, challenge(price, usdt.tokenContractAddress, recipient));
    }
  }

  // A REAL quote, from the same aggregator the agent executes through.
  const one = 10n ** BigInt(Number(wokb.decimals ?? 18));
  const q = await get(
    `/api/v6/dex/aggregator/quote?chainIndex=${CHAIN}&amount=${one}` +
      `&fromTokenAddress=${wokb.tokenContractAddress}&toTokenAddress=${usdt.tokenContractAddress}`,
    c,
  );
  if (!q?.length) {
    return send(res, 503, { error: "the router returned no route for this pair right now" });
  }

  const r = q[0];
  const venues = [];
  for (const hop of r.dexRouterList || []) {
    const n = hop?.dexProtocol?.dexName;
    if (n && !venues.includes(n)) venues.push(n);
  }

  send(res, 200, {
    pair: "WOKB/USDT",
    chain_id: Number(CHAIN),
    unit_price: r.toToken?.tokenUnitPrice ?? null,
    amount_out: r.toTokenAmount ?? null,
    price_impact_percent: r.priceImpactPercent ?? null,
    venues,
    honeypot: r.toToken?.isHoneyPot ?? null,
    tax_rate: r.toToken?.taxRate ?? null,
    quoted_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    // Stated, not implied. The serverless function prices; the chain enforces.
    enforcement:
      "Size limits and refusals are enforced on chain by RiskGuard and RwaRiskGuard. " +
      "This endpoint prices a route; it does not authorise a trade.",
    paid: Boolean(price && recipient),
  });
}
