/**
 * Every deployed contract's LIVE state, read from X Layer. No OKX key needed.
 *
 * WHY THIS BELONGS ON THE PRODUCT SURFACE. The footer already links nine contracts to the
 * explorer, which proves they exist and nothing else. What a person actually wants to know is
 * whether the machine is running and whether it is inside its own limits right now: how much
 * exposure is open against the cap, whether the kill switch is thrown, whether the vault is
 * solvent, what the fee actually is. Those are single `eth_call`s and they were not being made.
 *
 * SELECTORS ARE VERIFIED, NOT REMEMBERED. Every one below appears in
 * `evidence/phase20/contract-selectors.txt` beside a value that came back from the chain. Three
 * separate times in this project a selector written from memory returned `0x`, parsed as zero, and
 * turned an unread value into a confident "0" on screen. `agent()` and `paused()` REVERT on these
 * contracts, so they are deliberately absent here rather than shown as false.
 *
 * ABSENT IS ABSENT. A failed call yields null and the UI says the value could not be read.
 */

import { send } from "./_okx.js";
import { address, deployments as manifest } from "./_deployments.js";

const RPC = "https://rpc.xlayer.tech";

// Verified against the chain in scripts/229-contract-selectors.sh.
const SEL = {
  maxGross: "0xfb89278c",
  gross: "0x850f8017",
  killed: "0x1f3a0e41",
  owner: "0x8da5cb5b",
  orderCount: "0x2453ffa8",
  venueOwner: "0x71ecd9f3",
  feeBps: "0x24a9d853",
  chargeCount: "0x134e0cdd",
  treasury: "0x61d027b3",
  totalDeposits: "0x7d882097",
  totalCommitted: "0x1d3231d4",
  isSolvent: "0x5ce23950",
};

async function call(to, data) {
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

const big = (h) => (h ? BigInt(h) : null);
const bool = (h) => (h === null ? null : BigInt(h) === 1n);

/** 18-decimal amount to a readable string. Never rounds a real balance to nothing. */
function units(v) {
  if (v === null) return null;
  const whole = v / 10n ** 18n;
  const frac = (v % 10n ** 18n).toString().padStart(18, "0").slice(0, 4).replace(/0+$/, "");
  return frac ? `${whole}.${frac}` : whole.toString();
}

export default async function handler(req, res) {
  const guard = address("RiskGuard");
  const venue = address("OrderBookVenue");
  const batch = address("BatchExecutor");
  const fee = address("FeeCollector");
  const vault = address("AgentVault");
  const rwaVault = address("RwaVault");

  const [
    maxGross, gross, killed,
    orderCount, venueOwner,
    batchOwner,
    feeBps, chargeCount, treasury,
    totalDeposits, totalCommitted, isSolvent,
  ] = await Promise.all([
    call(guard, SEL.maxGross), call(guard, SEL.gross), call(guard, SEL.killed),
    call(venue, SEL.orderCount), call(venue, SEL.venueOwner),
    call(batch, SEL.owner),
    call(fee, SEL.feeBps), call(fee, SEL.chargeCount), call(fee, SEL.treasury),
    call(vault, SEL.totalDeposits), call(vault, SEL.totalCommitted), call(vault, SEL.isSolvent),
  ]);

  const cap = big(maxGross);
  const used = big(gross);
  // How much of the on-chain ceiling is in use. The single number that says whether the machine is
  // near its own edge.
  const usedPct =
    cap && used !== null && cap > 0n ? Number((used * 10000n) / cap) / 100 : null;

  send(res, 200, {
    source: "eth_call against the deployed contracts on X Layer mainnet",
    chain_id: manifest()?.chain_id ?? 196,
    explorer: manifest()?.explorer_address_base ?? "https://www.oklink.com/x-layer/evm/address/",
    fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),

    contracts: [
      {
        name: "Safety limits",
        contract: "RiskGuard",
        address: guard,
        plain: "The ceiling every trade is checked against, held on chain rather than in the app.",
        facts: [
          { label: "Most it may hold at once", value: units(cap) },
          { label: "Holding right now", value: units(used) },
          { label: "Share of the ceiling in use", value: usedPct === null ? null : `${usedPct.toFixed(2)}%` },
        ],
        status:
          killed === null
            ? null
            : bool(killed)
              ? { tone: "critical", text: "emergency stop is ON" }
              : { tone: "approved", text: "running normally" },
      },
      {
        name: "Your deposits",
        contract: "AgentVault",
        address: vault,
        plain: "Where your money sits. Withdrawal works even when the agent is paused.",
        facts: [
          { label: "Total deposited", value: units(big(totalDeposits)) },
          { label: "Committed to open trades", value: units(big(totalCommitted)) },
        ],
        status:
          isSolvent === null
            ? null
            : bool(isSolvent)
              ? { tone: "approved", text: "fully backed" }
              : { tone: "critical", text: "shortfall detected" },
      },
      {
        name: "Where orders execute",
        contract: "OrderBookVenue",
        address: venue,
        plain: "Settlement for the agent's own book. Real trades route through OKX pools instead.",
        facts: [
          { label: "Orders ever placed", value: big(orderCount)?.toString() ?? null },
          { label: "Operated by", value: venueOwner ? `0x…${venueOwner.slice(-6)}` : null },
        ],
        status: null,
      },
      {
        name: "What it costs you",
        contract: "FeeCollector",
        address: fee,
        plain: "Charged only on a trade that executes. Never on a deposit, never on a withdrawal.",
        facts: [
          {
            label: "Fee per trade",
            value: feeBps === null ? null : `${Number(BigInt(feeBps)) / 100}%`,
          },
          { label: "Times charged", value: big(chargeCount)?.toString() ?? null },
          { label: "Paid to", value: treasury ? `0x…${treasury.slice(-6)}` : null },
        ],
        status:
          feeBps === null
            ? null
            : { tone: "approved", text: "capped at 1% by the contract" },
      },
      {
        name: "Submits approved trades",
        contract: "BatchExecutor",
        address: batch,
        plain: "The only path from a decision to the chain, and it accepts approved actions only.",
        facts: [{ label: "Operated by", value: batchOwner ? `0x…${batchOwner.slice(-6)}` : null }],
        status: null,
      },
      {
        name: "Real-world asset rules",
        contract: "RwaRiskGuard",
        address: address("RwaRiskGuard"),
        plain: "A second set of refusals that only mean anything for an asset backed by something real.",
        facts: [{ label: "Paired vault", value: rwaVault ? `0x…${rwaVault.slice(-6)}` : null }],
        status: { tone: "approved", text: "see Your limits for the live values" },
      },
    ],
  });
}
