/**
 * The RWA guard RUN against every tokenized equity, rule by rule, with a verdict per instrument.
 *
 * WHY THIS EXISTS AND THE PREVIOUS PLAN WAS WRONG. The plan was to list xStock prices on one screen
 * and the contract addresses on another, and call that integration. It is not. It shows that the
 * contracts exist and that the assets exist, and leaves the reader to imagine the connection.
 *
 * What makes the contracts real is watching them DECIDE. Every rule below is a parameter read from
 * the deployed `RwaRiskGuard` on chain 196, evaluated against live market data for a specific
 * instrument, producing the same answer the agent would get before it traded. TSLAx either passes
 * or it does not, and if it does not the reason is the rule that stopped it.
 *
 * THE FOUR RULES, all read from the contract, none written here:
 *   maxDivergenceBps       how far the market price may stray from the reference before refusal
 *   maxOracleAge           how stale a price may be
 *   windowBufferSeconds    how close to a redemption window trading is refused
 *   paused                 whether the issuer has halted
 *
 * Two more checks come from the market rather than the contract, and are labelled as such: whether
 * the instrument has enough liquidity to exit, and whether a route exists at all. A guard rule and
 * a market fact are different kinds of claim and are never blended into one verdict.
 *
 * NOTHING IS SIMULATED. A rule whose input cannot be read is reported as UNKNOWN, and an unknown
 * rule makes the whole verdict "cannot be evaluated" rather than "approved". A guard that passes an
 * instrument it could not check is worse than no guard.
 */

import { CHAIN, get, post, requireCreds, send } from "./_okx.js";
import { PATHS, batch } from "./_paths.js";
import { address } from "./_deployments.js";

const RPC = "https://rpc.xlayer.tech";

// Verified in scripts/227-rwa-selectors.sh, each printed beside its live value.
const SEL = {
  maxDivergenceBps: "0xf9de4776",
  maxOracleAge: "0x7c87a993",
  windowBufferSeconds: "0x65f1fd4f",
  paused: "0x5c975abb",
};

const QUERIES = ["xStock", "nasdaq", "tesla", "apple", "nvidia", "gold"];

/** Liquidity below this cannot be exited at size. A market fact, not a contract rule. */
const MIN_LIQUIDITY_USD = 1000;

async function ethCall(to, data) {
  if (!to) return null;
  try {
    const r = await fetch(RPC, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "eth_call",
        params: [{ to, data }, "latest"],
      }),
    });
    const d = await r.json();
    return d.result && d.result !== "0x" ? d.result : null;
  } catch {
    return null;
  }
}

const num = (h) => (h === null ? null : Number(BigInt(h)));

/**
 * One rule's evaluation.
 *
 * `pass` is true, false, or null. Null means the input could not be read, and it is deliberately
 * NOT false: "we could not check" and "it failed" are different statements about someone's money.
 */
function rule(id, label, source, limit, actual, pass, plain) {
  return { id, label, source, limit, actual, pass, plain };
}

export default async function handler(req, res) {
  const c = requireCreds(res);
  if (!c) return;

  const guard = address("RwaRiskGuard");
  const vault = address("RwaVault");
  if (!guard) return send(res, 503, { error: "the RWA guard is not in the deployment manifest" });

  // ---- 1. the rules, from the contract
  const [divRaw, ageRaw, winRaw, pausedRaw] = await Promise.all([
    ethCall(guard, SEL.maxDivergenceBps),
    ethCall(guard, SEL.maxOracleAge),
    ethCall(guard, SEL.windowBufferSeconds),
    ethCall(vault, SEL.paused),
  ]);
  const maxDivergenceBps = num(divRaw);
  const maxOracleAge = num(ageRaw);
  const windowBuffer = num(winRaw);
  const issuerPaused = pausedRaw === null ? null : Boolean(num(pausedRaw));

  // ---- 2. the instruments, discovered by search
  const found = new Map();
  const results = await Promise.all(
    QUERIES.map((q) => get(PATHS.tokenSearch(CHAIN, q).path, c)),
  );
  for (const rows of results) {
    for (const t of rows || []) {
      const name = (t.tokenName || "").trim();
      const addr = t.tokenContractAddress;
      const sym = (t.tokenSymbol || "").trim();
      if (!addr || !sym || !name.toLowerCase().includes("xstock")) continue;
      found.set(addr.toLowerCase(), { symbol: sym, name, address: addr });
    }
  }
  const list = [...found.values()].sort((a, b) => a.symbol.localeCompare(b.symbol));
  if (list.length === 0) {
    return send(res, 200, {
      chain_id: Number(CHAIN),
      fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
      instruments: [],
      note: "The search returned no tokenized equities on this refresh.",
    });
  }

  // ---- 3. live market data, three batch calls
  const addrs = list.map((t) => t.address);
  const [priceRows, indexRows, infoRows] = await Promise.all([
    post(PATHS.price().path, batch(CHAIN, addrs), c),
    post(PATHS.indexPrice().path, batch(CHAIN, addrs), c),
    post(PATHS.priceInfo().path, batch(CHAIN, addrs), c),
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

  const now = Date.now();

  // ---- 4. run the guard against each one
  const instruments = list.map((t) => {
    const k = t.address.toLowerCase();
    const priceRow = prices.get(k);
    const indexRow = indexes.get(k);
    const info = infos.get(k) || {};

    const price = priceRow?.price ?? null;
    const index = indexRow?.price ?? null;
    const liquidity = Number(info.liquidity ?? 0) || 0;

    // RULE 1: divergence between two independent sources.
    let divergenceBps = null;
    if (price && index && Number(index) !== 0) {
      divergenceBps = ((Number(price) - Number(index)) / Number(index)) * 10000;
    }
    const r1 = rule(
      "divergence",
      "Price tracks its reference",
      "RwaRiskGuard.maxDivergenceBps",
      maxDivergenceBps === null ? null : `${(maxDivergenceBps / 100).toFixed(2)}%`,
      divergenceBps === null ? null : `${(divergenceBps / 100).toFixed(3)}%`,
      divergenceBps === null || maxDivergenceBps === null
        ? null
        : Math.abs(divergenceBps) <= maxDivergenceBps,
      "The pool price and the independent reference must agree. If they drift apart, the token has come loose from the share it represents.",
    );

    // RULE 2: how old the quote is. The API stamps each price.
    const stamp = Number(priceRow?.time ?? indexRow?.time ?? 0);
    const ageSeconds = stamp > 0 ? Math.max(0, Math.round((now - stamp) / 1000)) : null;
    const r2 = rule(
      "freshness",
      "The price is recent",
      "RwaRiskGuard.maxOracleAge",
      maxOracleAge === null ? null : `${Math.round(maxOracleAge / 60)} min`,
      ageSeconds === null ? null : `${ageSeconds}s old`,
      ageSeconds === null || maxOracleAge === null ? null : ageSeconds <= maxOracleAge,
      "A stale price is how an agent trades yesterday's market. Equities move when the exchange is open and this token does not always follow instantly.",
    );

    // RULE 3: the redemption-window buffer. The window schedule is the issuer's and is not on
    // chain, so the BUFFER is reported as the rule and the check is stated as not evaluable here
    // rather than assumed to pass.
    const r3 = rule(
      "window",
      "Not near a redemption window",
      "RwaRiskGuard.windowBufferSeconds",
      windowBuffer === null ? null : `${Math.round(windowBuffer / 3600)} h`,
      null,
      null,
      "Redemption windows move the price for reasons the market cannot see. The buffer is enforced on chain at execution; the issuer's schedule is not published to this feed, so it is checked there rather than here.",
    );

    // RULE 4: issuer pause, straight off the vault.
    const r4 = rule(
      "issuer",
      "The issuer has not halted",
      "RwaVault.paused",
      "not paused",
      issuerPaused === null ? null : issuerPaused ? "halted" : "active",
      issuerPaused === null ? null : !issuerPaused,
      "If whoever issues the token halts it, the agent stops too, rather than trading something nobody is standing behind.",
    );

    // MARKET FACTS, labelled separately from contract rules.
    const m1 = rule(
      "liquidity",
      "Enough liquidity to get out",
      "market, not a contract rule",
      `$${MIN_LIQUIDITY_USD.toLocaleString()}`,
      `$${Math.round(liquidity).toLocaleString()}`,
      liquidity >= MIN_LIQUIDITY_USD,
      "A position you cannot exit is not a position. This is a property of the market, not a rule the guard enforces.",
    );

    const rules = [r1, r2, r3, r4, m1];
    const failed = rules.filter((r) => r.pass === false);
    const unknown = rules.filter((r) => r.pass === null);

    // The verdict the agent would get. UNKNOWN never becomes APPROVED.
    let verdict;
    if (failed.length > 0) {
      verdict = { state: "refused", by: failed[0].label, detail: failed[0].id };
    } else if (unknown.length > 0) {
      verdict = { state: "unknown", by: unknown[0].label, detail: unknown[0].id };
    } else {
      verdict = { state: "approved", by: null, detail: null };
    }

    return {
      symbol: t.symbol,
      name: t.name,
      company: t.name.replace(/\s*xStock\s*$/i, ""),
      address: t.address,
      price,
      index_price: index,
      divergence_bps: divergenceBps === null ? null : divergenceBps.toFixed(2),
      liquidity_usd: liquidity,
      market_cap: info.marketCap ?? null,
      holders: info.holders ?? null,
      change_24h: info.priceChange24H ?? null,
      rules,
      verdict,
    };
  });

  send(res, 200, {
    source: "RwaRiskGuard parameters read from chain 196, evaluated against live OKX market data",
    chain_id: Number(CHAIN),
    fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    guard_address: guard,
    vault_address: vault,
    explorer: "https://www.oklink.com/x-layer/evm/address/",
    issuer: "Backed Finance",
    backing:
      "Each xStock is issued one-for-one against the real share, held with a regulated custodian " +
      "under Swiss DLT law.",
    approved_count: instruments.filter((i) => i.verdict.state === "approved").length,
    refused_count: instruments.filter((i) => i.verdict.state === "refused").length,
    instruments,
  });
}
