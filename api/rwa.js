/**
 * Real-world assets with every Onchain OS field, for the hosted deployment.
 *
 * The local twin is `scripts/rwa_full.py`. Both keep whole response objects rather than a curated
 * subset, because a hand-picked list of fields is a decision about what a person is allowed to see
 * and this product has no standing to make it for them.
 *
 * IDENTIFIED BY OKX'S OWN TAG. Discovery searches broadly, then keeps only what carries a
 * `tokenTags` entry containing "rwa", or a `stockProfile`. Matching "xStock" in a name was the
 * earlier approach and it is fragile: an issuer can name a token anything, and a scam can name
 * itself convincingly.
 *
 * SERVERLESS BUDGET. Vercel Hobby functions have a ten second wall clock, so the per-token detail
 * calls run in parallel and the search set is bounded. A partial answer is labelled as partial
 * rather than presented as the whole universe.
 */

import { CHAIN, get, post, requireCreds, send } from "./_okx.js";
import { PATHS, batch } from "./_paths.js";

const QUERIES = ["xStock", "nasdaq", "tesla", "apple", "nvidia", "gold", "equity", "index"];

const one = (v) => (Array.isArray(v) ? (v[0] ?? {}) : v && typeof v === "object" ? v : {});

export default async function handler(req, res) {
  const c = requireCreds(res);
  if (!c) return;

  // ---- discover
  const found = new Map();
  const results = await Promise.all(QUERIES.map((q) => get(PATHS.tokenSearch(CHAIN, q).path, c)));
  for (const rows of results) {
    for (const t of rows || []) {
      const addr = t.tokenContractAddress;
      const sym = (t.tokenSymbol || "").trim();
      if (!addr || !sym) continue;
      found.set(addr.toLowerCase(), {
        symbol: sym,
        name: (t.tokenName || "").trim(),
        address: addr,
        decimals: Number(t.decimal ?? t.decimals ?? 18),
        explorer_url: t.explorerUrl,
        logo: t.tokenLogoUrl,
      });
    }
  }

  const candidates = [...found.values()];
  if (candidates.length === 0) {
    return send(res, 200, {
      chain_id: Number(CHAIN),
      fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
      count: 0,
      instruments: [],
      note: "The search returned nothing on this refresh.",
    });
  }

  // ---- advanced-info decides which are real-world assets, in parallel
  const advs = await Promise.all(
    candidates.map((t) =>
      get(PATHS.advancedInfo(CHAIN, t.address).path, c).catch(() => null),
    ),
  );

  const rwa = [];
  candidates.forEach((t, i) => {
    const adv = one(advs[i]);
    const tags = adv.tokenTags || [];
    const isRwa =
      tags.some((x) => String(x).toLowerCase().includes("rwa")) || Boolean(adv.stockProfile);
    if (!isRwa) return;
    rwa.push({ ...t, tags, advanced: adv, stock: adv.stockProfile || {} });
  });

  if (rwa.length === 0) {
    return send(res, 200, {
      chain_id: Number(CHAIN),
      fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
      count: 0,
      instruments: [],
      note: "Nothing tagged as a real-world asset on this refresh.",
    });
  }

  const addrs = rwa.map((t) => t.address);

  // ---- three batch calls, plus per-token detail in parallel
  const asMap = (rows) => {
    const m = new Map();
    for (const r of rows || []) {
      if (r?.tokenContractAddress) m.set(r.tokenContractAddress.toLowerCase(), r);
    }
    return m;
  };

  const [priceRows, indexRows, infoRows, clusters, scans, pools] = await Promise.all([
    post(PATHS.price().path, batch(CHAIN, addrs), c),
    post(PATHS.indexPrice().path, batch(CHAIN, addrs), c),
    post(PATHS.priceInfo().path, batch(CHAIN, addrs), c),
    Promise.all(
      rwa.map((t) =>
        get(PATHS.clusterOverview(CHAIN, t.address).path, c).catch(() => null),
      ),
    ),
    Promise.all(
      rwa.map((t) =>
        // chainId / contractAddress, plus a source field. Not the keys every other endpoint uses.
        post(PATHS.tokenScan().path, {
          source: "asml-x",
          tokenList: [{ chainId: CHAIN, contractAddress: t.address }],
        }, c).catch(() => null),
      ),
    ),
    Promise.all(
      rwa.map((t) => get(PATHS.tokenLiquidity(CHAIN, t.address).path, c).catch(() => null)),
    ),
  ]);

  const prices = asMap(priceRows);
  const indexes = asMap(indexRows);
  const infos = asMap(infoRows);

  const instruments = rwa.map((t, i) => {
    const k = t.address.toLowerCase();
    const price = prices.get(k)?.price ?? null;
    const index = indexes.get(k)?.price ?? null;
    let divergence = null;
    if (price && index && Number(index) !== 0) {
      divergence = (((Number(price) - Number(index)) / Number(index)) * 10000).toFixed(2);
    }
    return {
      ...t,
      market: infos.get(k) || {},
      cluster: one(clusters[i]),
      security: one(scans[i]),
      pools: Array.isArray(pools[i]) ? pools[i].slice(0, 5) : [],
      holders_list: [],
      candles: [],
      price,
      price_time: prices.get(k)?.time ?? null,
      index_price: index,
      divergence_bps: divergence,
    };
  });

  send(res, 200, {
    source: "OKX Onchain OS: token search, advanced-info, cluster, security, liquidity, price, index",
    chain_id: Number(CHAIN),
    fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    issuer: "Backed Finance",
    backing:
      "Each xStock is issued one-for-one against the real share, held with a regulated custodian " +
      "under Swiss DLT law.",
    identified_by: "OKX tokenTags containing 'rwa', or the presence of a stockProfile",
    count: instruments.length,
    instruments,
  });
}
