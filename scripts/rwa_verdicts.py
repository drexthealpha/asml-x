"""Run the deployed RWA guard against every tokenized equity, and write the verdicts.

The hosted twin is `api/rwa-verdicts.js`. Both must produce the same shape, or the product behaves
differently depending on where it is served from.

WHAT THIS PROVES that a price list does not. Each rule is a parameter read from `RwaRiskGuard` on
chain 196, evaluated against live OKX market data for a specific instrument. TSLAx either passes or
it does not, and when it does not, the rule that stopped it is named. That is the contract doing
something, rather than being described.

UNKNOWN IS NOT APPROVED. A rule whose input could not be read makes the whole verdict
"cannot be evaluated". A guard that waves through an instrument it never checked is worse than no
guard, because it produces a green badge nobody earned.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "ui-v2", "public", "data", "rwa-verdicts.json")
CHAIN = "196"
MIN_LIQUIDITY_USD = 1000

# Verified in scripts/227-rwa-selectors.sh, each printed beside its live value.
SEL = {
    "maxDivergenceBps": "0xf9de4776",
    "maxOracleAge": "0x7c87a993",
    "windowBufferSeconds": "0x65f1fd4f",
    "paused": "0x5c975abb",
}

QUERIES = ["xStock", "nasdaq", "tesla", "apple", "nvidia", "gold"]

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from okx_dex import creds, signed_get, signed_post  # noqa: E402


def eth_call(rpc, to, selector):
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
        return int(result, 16) if result and result != "0x" else None
    except Exception:
        return None


def rule(rid, label, source, limit, actual, passed, plain):
    return {
        "id": rid, "label": label, "source": source,
        "limit": limit, "actual": actual, "pass": passed, "plain": plain,
    }


def main():
    c = creds()
    if not c:
        print("no credentials")
        return 1

    with open(os.path.join(REPO, "deployments-mainnet.json"), encoding="utf-8") as fh:
        m = json.load(fh)
    rpc, guard, vault = m["rpc"], m.get("rwaRiskGuard"), m.get("rwaVault")

    max_div = eth_call(rpc, guard, SEL["maxDivergenceBps"])
    max_age = eth_call(rpc, guard, SEL["maxOracleAge"])
    window = eth_call(rpc, guard, SEL["windowBufferSeconds"])
    paused_raw = eth_call(rpc, vault, SEL["paused"])
    issuer_paused = None if paused_raw is None else bool(paused_raw)

    print(f"guard rules read from chain {m['chainId']}")
    print(f"  max divergence   {max_div} bps")
    print(f"  max oracle age   {max_age} s")
    print(f"  window buffer    {window} s")
    print(f"  issuer paused    {issuer_paused}")

    # Discover the instruments by search.
    found = {}
    for q in QUERIES:
        r = signed_get(
            f"/api/v6/dex/market/token/search?chains={CHAIN}&search={q}&limit=50", c
        )
        for t in (r or {}).get("data") or []:
            name = (t.get("tokenName") or "").strip()
            addr = t.get("tokenContractAddress")
            sym = (t.get("tokenSymbol") or "").strip()
            if addr and sym and "xstock" in name.lower():
                found[addr.lower()] = {"symbol": sym, "name": name, "address": addr}

    rows = sorted(found.values(), key=lambda x: x["symbol"])
    if not rows:
        print("no tokenized equities returned on this refresh")
        return 1
    print(f"\n{len(rows)} tokenized equities found")

    body = [{"chainIndex": CHAIN, "tokenContractAddress": t["address"]} for t in rows]
    prices = {r["tokenContractAddress"].lower(): r
              for r in (signed_post("/api/v6/dex/market/price", body, c) or {}).get("data") or []}
    indexes = {r["tokenContractAddress"].lower(): r
               for r in (signed_post("/api/v6/dex/index/current-price", body, c) or {}).get("data") or []}
    infos = {r["tokenContractAddress"].lower(): r
             for r in (signed_post("/api/v6/dex/market/price-info", body, c) or {}).get("data") or []}

    now_ms = time.time() * 1000
    out_rows = []

    for t in rows:
        k = t["address"].lower()
        pr, ix, info = prices.get(k), indexes.get(k), infos.get(k) or {}
        price = pr.get("price") if pr else None
        index = ix.get("price") if ix else None
        liquidity = float(info.get("liquidity") or 0)

        div_bps = None
        if price and index and float(index) != 0:
            div_bps = (float(price) - float(index)) / float(index) * 10_000

        stamp = float((pr or {}).get("time") or (ix or {}).get("time") or 0)
        age_s = max(0, round((now_ms - stamp) / 1000)) if stamp > 0 else None

        rules = [
            rule("divergence", "Price tracks its reference", "RwaRiskGuard.maxDivergenceBps",
                 None if max_div is None else f"{max_div / 100:.2f}%",
                 None if div_bps is None else f"{div_bps / 100:.3f}%",
                 None if div_bps is None or max_div is None else abs(div_bps) <= max_div,
                 "The pool price and the independent reference must agree. If they drift apart, "
                 "the token has come loose from the share it represents."),
            rule("freshness", "The price is recent", "RwaRiskGuard.maxOracleAge",
                 None if max_age is None else f"{round(max_age / 60)} min",
                 None if age_s is None else f"{age_s}s old",
                 None if age_s is None or max_age is None else age_s <= max_age,
                 "A stale price is how an agent trades yesterday's market."),
            rule("window", "Not near a redemption window", "RwaRiskGuard.windowBufferSeconds",
                 None if window is None else f"{round(window / 3600)} h", None, None,
                 "Redemption windows move the price for reasons the market cannot see. The buffer "
                 "is enforced on chain at execution; the issuer's schedule is not in this feed."),
            rule("issuer", "The issuer has not halted", "RwaVault.paused", "not paused",
                 None if issuer_paused is None else ("halted" if issuer_paused else "active"),
                 None if issuer_paused is None else not issuer_paused,
                 "If whoever issues the token halts it, the agent stops too."),
            rule("liquidity", "Enough liquidity to get out", "market, not a contract rule",
                 f"${MIN_LIQUIDITY_USD:,}", f"${round(liquidity):,}",
                 liquidity >= MIN_LIQUIDITY_USD,
                 "A position you cannot exit is not a position."),
        ]

        failed = [r for r in rules if r["pass"] is False]
        unknown = [r for r in rules if r["pass"] is None]
        if failed:
            verdict = {"state": "refused", "by": failed[0]["label"], "detail": failed[0]["id"]}
        elif unknown:
            verdict = {"state": "unknown", "by": unknown[0]["label"], "detail": unknown[0]["id"]}
        else:
            verdict = {"state": "approved", "by": None, "detail": None}

        out_rows.append({
            **t,
            "company": t["name"].replace(" xStock", ""),
            "price": price, "index_price": index,
            "divergence_bps": None if div_bps is None else f"{div_bps:.2f}",
            "liquidity_usd": liquidity,
            "market_cap": info.get("marketCap"), "holders": info.get("holders"),
            "change_24h": info.get("priceChange24H"),
            "rules": rules, "verdict": verdict,
        })

        mark = {"approved": "APPROVED", "refused": "REFUSED ", "unknown": "UNKNOWN "}[verdict["state"]]
        why = f" <- {verdict['by']}" if verdict["by"] else ""
        print(f"  {t['symbol']:<10} {mark} ${str(price)[:9]:<10} liq ${liquidity:>10,.0f}{why}")

    out = {
        "source": "RwaRiskGuard parameters read from chain 196, evaluated against live OKX data",
        "chain_id": int(CHAIN),
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "guard_address": guard,
        "vault_address": vault,
        "explorer": "https://www.oklink.com/x-layer/evm/address/",
        "issuer": "Backed Finance",
        "backing": ("Each xStock is issued one-for-one against the real share, held with a "
                    "regulated custodian under Swiss DLT law."),
        "approved_count": sum(1 for r in out_rows if r["verdict"]["state"] == "approved"),
        "refused_count": sum(1 for r in out_rows if r["verdict"]["state"] == "refused"),
        "instruments": out_rows,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)
    print(f"\n{out['approved_count']} approved, {out['refused_count']} refused")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
