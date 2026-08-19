"""Per-token detail. Everything Onchain OS knows about one asset, in one place.

WHY THIS EXISTS. The token rows were static: clicking one did nothing, because there was nothing
behind it. Meanwhile every one of these fields was already reachable and unused. That is not a
missing feature, it is data that was fetched and thrown away.

WHAT IS SHOWN AND WHY EACH ONE MATTERS TO SOMEONE DECIDING WHETHER TO BUY:

  price, 5m/1h/4h/24h change    is it moving, and over what horizon
  holders, circulating supply   how many people hold it, how much exists
  liquidity, market cap         can you get out, and at what size
  pools + protocol names        WHERE it trades: Aave, Uniswap V3, PotatoSwap
  lpBurnedPercent               can the liquidity be pulled out from under you
  bundleHoldingPercent          how much was bought in one coordinated block
  cluster concentration         are the "different" holders actually one entity
  top100HoldingsPercent         how concentrated ownership really is
  honeypot / buy / sell tax     can you sell it at all, and what it costs

THE CONCENTRATION FIGURES ARE THE POINT. A price and a chart make anything look tradable. "Top 100
wallets hold 92%" and "liquidity providers can still withdraw 62% of the pool" are the numbers that
tell a person they are the exit liquidity. They exist in the API; leaving them out while showing a
pretty chart would be the polished-surface-over-nothing failure this project keeps naming.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OOS = os.path.join(REPO, "scripts", "oos.sh")
OUT = os.path.join(REPO, "ui-v2", "public", "data", "detail.json")
CHAIN = "xlayer"
CHAIN_ID = "196"


def oos(*args, timeout=90):
    try:
        r = subprocess.run(
            ["bash", OOS, *[str(a) for a in args]],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
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


def detail(symbol, address):
    """One token, every field that answers a real question. Absent fields stay absent."""
    row = {"symbol": symbol, "address": address}

    info = first(oos("--chain", CHAIN, "token", "price-info", "--address", address))
    if info:
        row.update({
            "price": info.get("price"),
            "holders": info.get("holders"),
            "liquidity": info.get("liquidity"),
            "market_cap": info.get("marketCap"),
            "circulating_supply": info.get("circSupply"),
            "high": info.get("maxPrice"),
            "low": info.get("minPrice"),
            "change_5m": info.get("priceChange5M"),
            "change_1h": info.get("priceChange1H"),
            "change_4h": info.get("priceChange4H"),
            "change_24h": info.get("priceChange24H"),
        })

    pools = oos("--chain", CHAIN, "token", "liquidity", "--address", address) or []
    row["pools"] = [
        {
            "pool": p.get("pool"),
            "protocol": p.get("protocolName"),
            "usd": p.get("liquidityUsd"),
            "address": p.get("poolAddress"),
        }
        for p in pools[:5]
    ]

    adv = oos("--chain", CHAIN, "token", "advanced-info", "--address", address)
    if isinstance(adv, dict):
        row["lp_burned_percent"] = adv.get("lpBurnedPercent")
        row["bundle_holding_percent"] = adv.get("bundleHoldingPercent")
        row["sniper_holding_percent"] = adv.get("sniperHoldingPercent")
        row["risk_control_level"] = adv.get("riskControlLevel")

    cl = oos("--chain", CHAIN, "token", "cluster-overview", "--address", address)
    if isinstance(cl, dict):
        row["cluster_concentration"] = cl.get("ClusterConcentration")
        row["top100_percent"] = cl.get("top100HoldingsPercent")
        row["same_funder_percent"] = cl.get("holderSameFundSourcePercent")

    scan = first(oos("--chain", CHAIN, "security", "token-scan", "--tokens", f"{CHAIN_ID}:{address}"))
    if scan:
        row["honeypot"] = scan.get("isHoneypot")
        row["risk_level"] = scan.get("riskLevel")
        row["buy_tax"] = scan.get("buyTaxes")
        row["sell_tax"] = scan.get("sellTaxes")
        row["mintable"] = scan.get("isMintable")
        row["open_source"] = None if scan.get("isNotOpenSource") is None else (
            not scan.get("isNotOpenSource")
        )
        row["low_liquidity"] = scan.get("isLowLiquidity")

    idx = first(oos("--chain", CHAIN, "market", "index", "--address", address))
    row["index_price"] = idx.get("price") if idx else None

    return row


def main():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import tokens as tokenlist
    from okx_dex import creds

    c = creds()
    if not c:
        print("no credentials")
        return 1

    try:
        listed = tokenlist.all_tokens(c)
    except tokenlist.TokenNotListed as e:
        print(f"token list unavailable: {e}")
        return 1

    # EVERY TOKEN THE UI CAN NAME gets a record, not just the aggregator-listed ones.
    #
    # A row that clicks and does nothing is worse than a row that does not click: it reads as
    # broken rather than as static. The Insights surface names tokens from the smart-money feed
    # (STARCOIN, RTX, GPU) which are NOT in the aggregator's 22, so those rows opened nothing.
    # Anything the product is willing to put on screen, it must be willing to explain.
    targets = {sym: t["address"] for sym, t in listed.items()}

    intel_path = os.path.join(REPO, "ui-v2", "public", "data", "intel.json")
    try:
        with open(intel_path, encoding="utf-8") as fh:
            for s in json.load(fh).get("smart_money", []):
                if s.get("symbol") and s.get("address"):
                    targets.setdefault(s["symbol"], s["address"])
    except (OSError, json.JSONDecodeError):
        # The intel feed may not have run yet. The listed tokens still get their records.
        pass

    rows = {}
    for sym, address in sorted(targets.items()):
        d = detail(sym, address)
        rows[sym] = d
        print(f"  {sym:<14} holders {str(d.get('holders')):>8}  "
              f"pools {len(d.get('pools') or [])}  risk {d.get('risk_level')}")

    out = {
        "source": "OKX Onchain OS, per-token detail",
        "chain_id": int(CHAIN_ID),
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "tokens": rows,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)
    print(f"\n{len(rows)} tokens detailed")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
