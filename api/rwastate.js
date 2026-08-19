/**
 * The RWA guard's live parameters, read straight off X Layer. Hosted equivalent of `rwa_state.py`.
 *
 * NO OKX KEY NEEDED. This is a public RPC and public contract state, so it works on any deployment
 * whether or not credentials are configured. That matters: the safety rules are the part of this
 * product a stranger most needs to be able to verify, and they should never be gated behind a key
 * the visitor does not have.
 *
 * SELECTORS ARE COMPUTED, NOT REMEMBERED. Three separate times in this project a selector written
 * from memory returned `0x`, parsed as zero, and reported an unread value as a verified one. These
 * come from `cast sig` and are checked by `scripts/227-rwa-selectors.sh`, which reads each live
 * value in the same run.
 */

import { send } from "./_okx.js";

const RPC = "https://rpc.xlayer.tech";

const SEL = {
  maxDivergenceBps: "0xf9de4776",
  maxOracleAge: "0x7c87a993",
  windowBufferSeconds: "0x65f1fd4f",
  paused: "0x5c975abb",
};

// The deployed addresses. These come from `deployments-mainnet.json`, which is written by the
// deploy scripts from the deployment that actually happened, and is bundled at build time.
import { address, deployments as manifest } from "./_deployments.js";

async function call(to, data) {
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

const asInt = (h) => (h ? Number(BigInt(h)) : null);

const mins = (s) =>
  s === null ? null : s >= 60 ? `${Math.round(s / 60)} minutes` : `${s} seconds`;

export default async function handler(req, res) {
  const guard = address("RwaRiskGuard");
  const vault = address("RwaVault");
  if (!guard || !vault) {
    return send(res, 503, { error: "the RWA contracts are not in the deployment manifest" });
  }

  const [div, age, buf, pausedRaw] = await Promise.all([
    call(guard, SEL.maxDivergenceBps),
    call(guard, SEL.maxOracleAge),
    call(guard, SEL.windowBufferSeconds),
    call(vault, SEL.paused),
  ]);

  const divergence = asInt(div);
  const oracleAge = asInt(age);
  const windowBuf = asInt(buf);
  const paused = pausedRaw === null ? null : Boolean(asInt(pausedRaw));

  send(res, 200, {
    source: "eth_call against the deployed RWA contracts on X Layer mainnet",
    chain_id: manifest()?.chain_id ?? 196,
    explorer: manifest()?.explorer_address_base ?? "https://www.oklink.com/x-layer/evm/address/",
    fetched_at_utc: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    guard_address: guard,
    vault_address: vault,
    vault_paused: paused,
    rules: [
      {
        name: "Price must track its reference",
        plain:
          "If the market price drifts further than this from the reference price, the agent stops trading it.",
        value_bps: divergence,
        display: divergence === null ? null : `${(divergence / 100).toFixed(2)}%`,
      },
      {
        name: "The price must be recent",
        plain:
          "A price older than this is refused. Stale data on a real-world asset is how an agent trades yesterday's market.",
        value_seconds: oracleAge,
        display: mins(oracleAge),
      },
      {
        name: "No trading near a redemption window",
        plain:
          "Real-world assets have windows where they can be redeemed. Trading close to one is refused, because the price moves for reasons the agent cannot see.",
        value_seconds: windowBuf,
        display: mins(windowBuf),
      },
      {
        name: "The issuer must not be paused",
        plain:
          "If whoever issues the asset halts it, the agent stops too, rather than trading something nobody is standing behind.",
        value_bool: paused,
        display: paused === null ? null : paused ? "halted" : "active",
      },
    ],
    unreadable: Object.entries({
      maxDivergenceBps: divergence,
      maxOracleAge: oracleAge,
      windowBufferSeconds: windowBuf,
    })
      .filter(([, v]) => v === null)
      .map(([k]) => k),
  });
}
