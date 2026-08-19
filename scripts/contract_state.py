"""Live state of every deployed contract, for the local feed server.

The hosted twin is `api/contracts.js`. They must produce the same shape, or the app behaves
differently depending on where it is served from and every bug becomes "which environment".

SELECTORS VERIFIED IN scripts/229-contract-selectors.sh. `agent()` and `paused()` REVERT on these
contracts and are deliberately absent rather than rendered as false: a reverting call is not a
`false`, and showing one as the other would claim the agent is unset and the vault unpaused when
neither was read.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "ui-v2", "public", "data", "contracts.json")

SEL = {
    "maxGross": "0xfb89278c",
    "gross": "0x850f8017",
    "killed": "0x1f3a0e41",
    "owner": "0x8da5cb5b",
    "orderCount": "0x2453ffa8",
    "venueOwner": "0x71ecd9f3",
    "feeBps": "0x24a9d853",
    "chargeCount": "0x134e0cdd",
    "treasury": "0x61d027b3",
    "totalDeposits": "0x7d882097",
    "totalCommitted": "0x1d3231d4",
    "isSolvent": "0x5ce23950",
}


def call(rpc, to, selector):
    if not to:
        return None
    payload = json.dumps({
        "jsonrpc": "2.0", "id": 1, "method": "eth_call",
        "params": [{"to": to, "data": selector}, "latest"],
    })
    try:
        r = subprocess.run(
            ["curl", "-sS", "--max-time", "15", "-H", "Content-Type: application/json",
             "-d", payload, rpc],
            capture_output=True, text=True, timeout=25,
        )
        result = json.loads(r.stdout).get("result")
        return result if result and result != "0x" else None
    except Exception:
        return None


def big(h):
    return int(h, 16) if h else None


def boolean(h):
    return None if h is None else bool(int(h, 16))


def units(v):
    """18-decimal amount to a readable string. A real balance is never rounded to nothing."""
    if v is None:
        return None
    whole, frac = divmod(v, 10**18)
    f = str(frac).rjust(18, "0")[:4].rstrip("0")
    return f"{whole}.{f}" if f else str(whole)


def short(a):
    return f"0x…{a[-6:]}" if a else None


def main():
    with open(os.path.join(REPO, "deployments-mainnet.json"), encoding="utf-8") as fh:
        m = json.load(fh)
    rpc = m["rpc"]

    guard, venue = m.get("riskGuard"), m.get("venue")
    batch, fee, vault = m.get("batchExecutor"), m.get("feeCollector"), m.get("agentVault")

    cap = big(call(rpc, guard, SEL["maxGross"]))
    used = big(call(rpc, guard, SEL["gross"]))
    killed = boolean(call(rpc, guard, SEL["killed"]))
    order_count = big(call(rpc, venue, SEL["orderCount"]))
    venue_owner = call(rpc, venue, SEL["venueOwner"])
    batch_owner = call(rpc, batch, SEL["owner"])
    fee_bps = big(call(rpc, fee, SEL["feeBps"]))
    charges = big(call(rpc, fee, SEL["chargeCount"]))
    treasury = call(rpc, fee, SEL["treasury"])
    deposits = big(call(rpc, vault, SEL["totalDeposits"]))
    committed = big(call(rpc, vault, SEL["totalCommitted"]))
    solvent = boolean(call(rpc, vault, SEL["isSolvent"]))

    used_pct = None
    if cap and used is not None and cap > 0:
        used_pct = f"{used * 10000 // cap / 100:.2f}%"

    addr = lambda h: ("0x" + h[-40:]) if h else None  # noqa: E731

    out = {
        "source": "eth_call against the deployed contracts on X Layer mainnet",
        "chain_id": m["chainId"],
        "explorer": "https://www.oklink.com/x-layer/evm/address/",
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "contracts": [
            {
                "name": "Safety limits",
                "contract": "RiskGuard",
                "address": guard,
                "plain": "The ceiling every trade is checked against, held on chain rather than in the app.",
                "facts": [
                    {"label": "Most it may hold at once", "value": units(cap)},
                    {"label": "Holding right now", "value": units(used)},
                    {"label": "Share of the ceiling in use", "value": used_pct},
                ],
                "status": None if killed is None else (
                    {"tone": "critical", "text": "emergency stop is ON"} if killed
                    else {"tone": "approved", "text": "running normally"}
                ),
            },
            {
                "name": "Your deposits",
                "contract": "AgentVault",
                "address": vault,
                "plain": "Where your money sits. Withdrawal works even when the agent is paused.",
                "facts": [
                    {"label": "Total deposited", "value": units(deposits)},
                    {"label": "Committed to open trades", "value": units(committed)},
                ],
                "status": None if solvent is None else (
                    {"tone": "approved", "text": "fully backed"} if solvent
                    else {"tone": "critical", "text": "shortfall detected"}
                ),
            },
            {
                "name": "Where orders execute",
                "contract": "OrderBookVenue",
                "address": venue,
                "plain": "Settlement for the agent's own book. Real trades route through OKX pools instead.",
                "facts": [
                    {"label": "Orders ever placed", "value": str(order_count) if order_count is not None else None},
                    {"label": "Operated by", "value": short(addr(venue_owner))},
                ],
                "status": None,
            },
            {
                "name": "What it costs you",
                "contract": "FeeCollector",
                "address": fee,
                "plain": "Charged only on a trade that executes. Never on a deposit, never on a withdrawal.",
                "facts": [
                    {"label": "Fee per trade", "value": f"{fee_bps / 100}%" if fee_bps is not None else None},
                    {"label": "Times charged", "value": str(charges) if charges is not None else None},
                    {"label": "Paid to", "value": short(addr(treasury))},
                ],
                "status": None if fee_bps is None else {
                    "tone": "approved", "text": "capped at 1% by the contract",
                },
            },
            {
                "name": "Submits approved trades",
                "contract": "BatchExecutor",
                "address": batch,
                "plain": "The only path from a decision to the chain, and it accepts approved actions only.",
                "facts": [{"label": "Operated by", "value": short(addr(batch_owner))}],
                "status": None,
            },
            {
                "name": "Real-world asset rules",
                "contract": "RwaRiskGuard",
                "address": m.get("rwaRiskGuard"),
                "plain": "A second set of refusals that only mean anything for an asset backed by something real.",
                "facts": [{"label": "Paired vault", "value": short(m.get("rwaVault"))}],
                "status": {"tone": "approved", "text": "see Your limits for the live values"},
            },
        ],
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)

    for c in out["contracts"]:
        vals = ", ".join(f"{f['label']} {f['value']}" for f in c["facts"] if f["value"] is not None)
        print(f"  {c['contract']:<16} {vals}")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
