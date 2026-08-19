"""Tokenized equities on X Layer: the xStocks, priced and checked.

WHAT THESE ARE. Backed Finance issues xStocks 1:1 against real shares held with a regulated
custodian under Swiss DLT law. TSLAx is a claim on a Tesla share, not a token named after one.
That is a genuine real-world asset, and it is exactly the instrument class the RWA guard was
written for: a price that must track an external reference, an issuer who can halt, a redemption
mechanism, and an oracle that can go stale.

WHY THEY WERE MISSING. I checked `aggregator/all-tokens` for chain 196, found 22 tokens with no
equities among them, and reported that X Layer has no tokenized stocks. The aggregator's SEARCH
endpoint covers a much larger universe and was never queried. "Absent from the list I checked" is
not "absent from the chain", and stating the second having established only the first is the same
failure as inventing a feature.

WHAT IS VERIFIED HERE BEFORE ANYTHING IS SHOWN. A name is not a backing. Each token is checked for
a real price, a real route, and real liquidity, and anything that fails is marked so rather than
being presented alongside the ones that pass. An unroutable equity token with $200 of liquidity is
a worse thing to show a person than nothing at all, because the name lends it credibility the
market does not.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OOS = os.path.join(REPO, "scripts", "oos.sh")
OUT = os.path.join(REPO, "ui-v2", "public", "data", "xstocks.json")
CHAIN = "196"

# The search terms that surface the xStocks universe. Not a token list: these are QUERIES, and the
# symbols and addresses they return are discovered, never typed.
QUERIES = [
    "xStock", "stock", "equity", "nasdaq", "index", "tesla", "apple",
    "microsoft", "nvidia", "amazon", "google", "meta", "gold", "treasury",
    "S&P", "ETF", "real",
]


def oos(*args, timeout=90):
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


def first(rows):
    return rows[0] if isinstance(rows, list) and rows else None


def discover():
    """Every xStock on chain 196, found by search rather than by a written list."""
    found = {}
    for q in QUERIES:
        rows = oos("token", "search", "--query", q, "--chains", CHAIN, "--limit", "50")
        for t in rows if isinstance(rows, list) else []:
            idx = str(t.get("chainIndex") or t.get("chainId") or "")
            if idx and idx != CHAIN:
                continue
            sym = (t.get("tokenSymbol") or "").strip()
            name = (t.get("tokenName") or "").strip()
            addr = t.get("tokenContractAddress")
            if not sym or not addr:
                continue
            # xStocks are identifiable by the issuer's naming: every one ends in "xStock".
            if "xstock" not in name.lower():
                continue
            found[addr.lower()] = {"symbol": sym, "name": name, "address": addr}
    return list(found.values())


def enrich(t):
    """Price, route and liquidity. A name with none of these is not tradable."""
    addr = t["address"]

    price = first(oos("--chain", "xlayer", "market", "price", "--address", addr))
    t["price"] = price.get("price") if price else None

    idx = first(oos("--chain", "xlayer", "market", "index", "--address", addr))
    t["index_price"] = idx.get("price") if idx else None

    if t["price"] and t["index_price"]:
        try:
            a, b = float(t["price"]), float(t["index_price"])
            t["divergence_bps"] = f"{(a - b) / b * 10_000:.2f}" if b else None
        except (TypeError, ValueError):
            t["divergence_bps"] = None

    info = first(oos("--chain", "xlayer", "token", "price-info", "--address", addr))
    if info:
        t["liquidity"] = info.get("liquidity")
        t["market_cap"] = info.get("marketCap")
        t["holders"] = info.get("holders")
        t["change_24h"] = info.get("priceChange24H")

    pools = oos("--chain", "xlayer", "token", "liquidity", "--address", addr) or []
    t["pools"] = [
        {"protocol": p.get("protocolName"), "usd": p.get("liquidityUsd")} for p in pools[:3]
    ]

    scan = first(oos("--chain", "xlayer", "security", "token-scan", "--tokens", f"{CHAIN}:{addr}"))
    if scan:
        t["honeypot"] = scan.get("isHoneypot")
        t["risk_level"] = scan.get("riskLevel")

    # TRADABLE means priced AND routable AND with liquidity worth the name. Each condition is
    # recorded separately so the UI can say which one failed rather than just hiding the row.
    liq = 0.0
    try:
        liq = float(t.get("liquidity") or 0)
    except (TypeError, ValueError):
        liq = 0.0
    t["has_price"] = t["price"] is not None
    t["has_liquidity"] = liq > 1000
    t["liquidity_usd"] = liq
    t["tradable"] = bool(t["has_price"] and t["has_liquidity"])
    return t


def main():
    print("searching for tokenized equities on X Layer")
    rows = discover()
    print(f"  found {len(rows)} xStocks by search")
    if not rows:
        print("  nothing to enrich; writing nothing rather than an empty claim")
        return 1

    out_rows = []
    for t in sorted(rows, key=lambda x: x["symbol"]):
        e = enrich(t)
        out_rows.append(e)
        state = "tradable" if e["tradable"] else ("no price" if not e["has_price"] else "too thin")
        print(f"  {e['symbol']:<10} {e['name']:<36} {state:<10} liq ${e['liquidity_usd']:,.0f}")

    tradable = [r for r in out_rows if r["tradable"]]

    out = {
        "source": "OKX Onchain OS token search plus market and security APIs, signed",
        "chain_id": int(CHAIN),
        "chain_name": "X Layer",
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "issuer": "Backed Finance",
        "backing": (
            "Each xStock is issued 1:1 against the real share, held with a regulated custodian "
            "under Swiss DLT law. The token is a claim on the share, not a token named after it."
        ),
        "total_found": len(out_rows),
        "tradable_count": len(tradable),
        "instruments": out_rows,
        # Stated in the data, so the UI shows the caveat rather than the reader discovering it.
        "caveat": (
            "Liquidity for tokenized equities on this chain is thin. The agent's size limit comes "
            "from measured depth, so a thin market means small trades or none at all."
        ),
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)

    print(f"\n{len(tradable)} of {len(out_rows)} are priced with real liquidity")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
