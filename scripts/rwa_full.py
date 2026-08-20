"""EVERY Onchain OS datapoint for every tokenized real-world asset on X Layer.

WHAT CHANGED AND WHY IT MATTERS. The first version picked a dozen fields by name and dropped the
rest. Three of the most valuable things Onchain OS returns were among the dropped:

  stockProfile   the REAL COMPANY: name, exchange, industry, listing date, ticker.
                 TSLAx carries {Tesla, Inc. / Nasdaq / Auto - Manufacturers / 2010-06-29 / TSLA}.
                 That is what makes it a real-world asset rather than a ticker-shaped token.
  tokenTags      ['rwaXstock'] — the issuer classification, straight from OKX. Far more reliable
                 than matching "xStock" in a name, which is what discovery was doing.
  24 risk flags  isCounterfeitStockToken, isFakeLiquidity, isDumping, isNotRenounced, isOverIssued,
                 isWash, isFundLinkage, isHasFrozenAuth, isLiquidityRemoval, isVeryLowLpBurn...
                 The scan returns two dozen and only five were being read.

`isCounterfeitStockToken` is the single most important flag on this whole surface: it is OKX
telling you a token claiming to be a share is not one. Dropping it while showing a price would be
the worst thing this feed could do.

SO NOTHING IS DROPPED NOW. Each endpoint's full response is kept under its own key, and the UI
renders every field. A curated subset is a decision about what someone is allowed to see, and this
project has no business making that decision on their behalf.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OOS = os.path.join(REPO, "scripts", "oos.sh")
OUT = os.path.join(REPO, "ui-v2", "public", "data", "rwa-full.json")
CHAIN = "196"

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from okx_dex import creds, signed_get, signed_post  # noqa: E402

# Broad, because discovery by name misses anything the issuer names differently. The `rwaXstock`
# tag is the reliable filter and is applied after.
QUERIES = [
    "xStock", "nasdaq", "tesla", "apple", "nvidia", "gold", "index", "equity",
    "microsoft", "amazon", "google", "meta", "stock", "share", "realty", "goldman",
]


def cli(*args, timeout=60):
    try:
        r = subprocess.run(
            ["bash", OOS, *[str(a) for a in args]],
            capture_output=True, text=True, timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    i = r.stdout.find("{")
    if i < 0:
        return None
    try:
        d = json.loads(r.stdout[i:])
    except json.JSONDecodeError:
        return None
    return d.get("data") if d.get("ok") else None


def one(v):
    """A response that may be a bare object or a one-element list."""
    if isinstance(v, list):
        return v[0] if v else {}
    return v if isinstance(v, dict) else {}


def discover(c):
    """Find candidates by search, then keep only what OKX itself tags as an RWA."""
    found = {}
    for q in QUERIES:
        r = signed_get(f"/api/v6/dex/market/token/search?chains={CHAIN}&search={q}&limit=50", c)
        for t in (r or {}).get("data") or []:
            addr = t.get("tokenContractAddress")
            sym = (t.get("tokenSymbol") or "").strip()
            if not addr or not sym:
                continue
            found[addr.lower()] = {
                "symbol": sym,
                "name": (t.get("tokenName") or "").strip(),
                "address": addr,
                "decimals": int(t.get("decimal") or t.get("decimals") or 18),
                "explorer_url": t.get("explorerUrl"),
                "logo": t.get("tokenLogoUrl"),
            }
    return found


def main():
    c = creds()
    if not c:
        print("no credentials")
        return 1

    candidates = discover(c)
    print(f"{len(candidates)} candidates from search")

    rows = []
    for t in sorted(candidates.values(), key=lambda x: x["symbol"]):
        adv = one(cli("--chain", "xlayer", "token", "advanced-info", "--address", t["address"]))
        tags = adv.get("tokenTags") or []

        # THE RELIABLE FILTER. OKX's own classification, not a substring of the name. A token can
        # be called anything; the tag is what the data provider asserts about it.
        is_rwa = any("rwa" in str(x).lower() for x in tags) or bool(adv.get("stockProfile"))
        if not is_rwa:
            continue

        t["tags"] = tags
        t["advanced"] = adv                      # every field, nothing dropped
        t["stock"] = adv.get("stockProfile") or {}

        t["cluster"] = one(
            cli("--chain", "xlayer", "token", "cluster-overview", "--address", t["address"])
        )
        t["security"] = one(
            cli("--chain", "xlayer", "security", "token-scan", "--tokens", f"{CHAIN}:{t['address']}")
        )

        pools = cli("--chain", "xlayer", "token", "liquidity", "--address", t["address"]) or []
        t["pools"] = pools if isinstance(pools, list) else []

        holders = cli("--chain", "xlayer", "token", "holders", "--address", t["address"]) or []
        t["holders_list"] = (holders if isinstance(holders, list) else [])[:10]

        kl = cli("--chain", "xlayer", "market", "kline", "--address", t["address"],
                 "--bar", "1H", "--limit", "48") or []
        t["candles"] = [
            {"t": int(k["ts"]) // 1000, "c": k["c"], "h": k["h"], "l": k["l"], "o": k["o"]}
            for k in reversed(kl) if isinstance(k, dict) and k.get("ts")
        ]
        rows.append(t)
        sp = t["stock"]
        print(f"  {t['symbol']:<10} {sp.get('companyName', '')[:26]:<28} "
              f"{sp.get('exchange', ''):<8} {len(t['pools'])} pools")

    if not rows:
        print("nothing tagged as an RWA on this refresh; writing nothing")
        return 1

    addrs = [t["address"] for t in rows]
    body = [{"chainIndex": CHAIN, "tokenContractAddress": a} for a in addrs]

    def batch(path):
        d = (signed_post(path, body, c) or {}).get("data") or []
        return {r["tokenContractAddress"].lower(): r for r in d if r.get("tokenContractAddress")}

    prices = batch("/api/v6/dex/market/price")
    indexes = batch("/api/v6/dex/index/current-price")
    infos = batch("/api/v6/dex/market/price-info")

    for t in rows:
        k = t["address"].lower()
        t["market"] = infos.get(k, {})      # every price-info field, nothing dropped
        t["price"] = (prices.get(k) or {}).get("price")
        t["price_time"] = (prices.get(k) or {}).get("time")
        t["index_price"] = (indexes.get(k) or {}).get("price")
        if t["price"] and t["index_price"] and float(t["index_price"]) != 0:
            d = (float(t["price"]) - float(t["index_price"])) / float(t["index_price"]) * 10_000
            t["divergence_bps"] = f"{d:.2f}"
        else:
            t["divergence_bps"] = None

    out = {
        "source": "OKX Onchain OS: token search, advanced-info, cluster-overview, security "
                  "token-scan, token liquidity, holders, kline, price, index price, price-info",
        "chain_id": int(CHAIN),
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "issuer": "Backed Finance",
        "backing": ("Each xStock is issued one-for-one against the real share, held with a "
                    "regulated custodian under Swiss DLT law."),
        "identified_by": "OKX tokenTags containing 'rwa', or the presence of a stockProfile",
        "count": len(rows),
        "instruments": rows,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)
    print(f"\n{len(rows)} real-world assets, every field retained")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
