"""Every working Onchain OS surface, written to one file the UI reads.

VERIFIED SURFACES, probed by scripts/222-oos-probe.sh and listed here so nothing is claimed that
was not actually called:

  market price          token price, per chain
  market index          AGGREGATED index price, an independent second source
  market kline          OHLC at any bar size, up to 299 points
  token info            name, symbol, decimals
  token price-info      market cap, liquidity, 24h volume and change
  token liquidity       the top 5 real pools
  token advanced-info   creator, dev holdings, holder concentration, bundle percentage
  security token-scan   honeypot, tax, mint risk, from OKX's own scanner
  security approvals    outstanding allowances on an address
  signal chains         which chains carry smart-money signals
  defi search           live products with real APY and TVL
  swap quote            executable route with price impact and tax flags

WHY TWO PRICE SOURCES MATTER. `market price` is the DEX-derived price and `market index` is
aggregated across sources. The RWA guard exists to refuse trades where those two disagree, and
until now the project had no independent second source to compare against, so the divergence check
compared a price to itself. This is the missing input.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OOS = os.path.join(REPO, "scripts", "oos.sh")
OUT = os.path.join(REPO, "ui-v2", "public", "data", "onchainos.json")
CHAIN = "xlayer"
CHAIN_ID = "196"


def oos(*args, timeout=90):
    """Run one CLI command, return parsed JSON data or None.

    The CLI emits progress lines before its JSON, so parsing starts at the first brace. `ok: false`
    returns None rather than a partial: a caller must not be handed an error object shaped like
    data.
    """
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


def token_snapshot(symbol, address):
    """Everything Onchain OS knows about one token, in one row."""
    row = {"symbol": symbol, "address": address}

    p = first(oos("--chain", CHAIN, "market", "price", "--address", address))
    row["price"] = p.get("price") if p else None

    # The independent second source. Present separately, never averaged with the first: two
    # measurements that disagree are information, and averaging them destroys it.
    idx = first(oos("--chain", CHAIN, "market", "index", "--address", address))
    row["index_price"] = idx.get("price") if idx else None

    if row["price"] and row["index_price"]:
        try:
            a, b = float(row["price"]), float(row["index_price"])
            row["divergence_bps"] = f"{(a - b) / b * 10_000:.2f}" if b else None
        except (TypeError, ValueError):
            row["divergence_bps"] = None

    info = first(oos("--chain", CHAIN, "token", "price-info", "--address", address))
    if info:
        row["market_cap"] = info.get("marketCap")
        row["liquidity"] = info.get("liquidity")
        row["volume_24h"] = info.get("volume24H") or info.get("volume")
        row["change_24h"] = info.get("priceChange24H") or info.get("change24H")

    pools = oos("--chain", CHAIN, "token", "liquidity", "--address", address)
    row["pools"] = [
        {"dex": p.get("dexName") or p.get("dex"), "liquidity": p.get("liquidity")}
        for p in (pools or [])[:5]
    ]

    scan = first(oos("--chain", CHAIN, "security", "token-scan", "--tokens", f"{CHAIN_ID}:{address}"))
    if scan:
        row["honeypot"] = scan.get("isHoneyPot") or scan.get("honeypot")
        row["buy_tax"] = scan.get("buyTax")
        row["sell_tax"] = scan.get("sellTax")

    return row


def candles(address, bar="1m", limit=120):
    """Real OHLC. Reversed so time ascends, which is what a chart expects."""
    rows = oos("--chain", CHAIN, "market", "kline", "--address", address, "--bar", bar,
               "--limit", str(limit))
    out = []
    for k in reversed(rows or []):
        try:
            out.append({"t": int(k["ts"]) // 1000, "c": k["c"], "h": k["h"], "l": k["l"], "o": k["o"]})
        except (KeyError, TypeError, ValueError):
            continue
    return out


def defi(group="SINGLE_EARN", tokens="USDT,USDC,OKB"):
    raw = oos("defi", "search", "--chain", CHAIN, "--token", tokens, "--product-group", group)
    lst = (raw or {}).get("list") or (raw or {}).get("investments") or []
    return [
        {
            "platform": p.get("platformName"),
            "name": p.get("investmentName") or p.get("platformName"),
            "apy": p.get("rate"),
            "tvl": p.get("tvl"),
            "id": p.get("investmentId"),
            "group": group,
        }
        for p in lst
    ]


def main():
    # Discovered, never typed. Same rule as everywhere else in this project.
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

    print(f"chain {CHAIN_ID}: {len(listed)} tokens listed")

    # Enriched for the tokens with real liquidity. Every token gets a price in universe.json
    # already; this adds the deeper reads where they are worth the calls.
    focus = ["WOKB", "USDT", "USDC", "ETH", "WBTC", "xBTC", "DAI", "USDG"]
    rows = []
    for sym in focus:
        t = listed.get(sym)
        if not t:
            continue
        r = token_snapshot(sym, t["address"])
        rows.append(r)
        div = r.get("divergence_bps")
        print(f"  {sym:<7} ${r.get('price') and float(r['price']):<12.6f} "
              f"index {r.get('index_price')}  divergence {div} bps")

    wokb = listed.get("WOKB", {}).get("address")
    series = candles(wokb) if wokb else []
    print(f"  candles: {len(series)}")

    earn = defi()
    lending = defi(group="LENDING")
    pools = defi(group="DEX_POOL")
    print(f"  defi: {len(earn)} earn, {len(lending)} lending, {len(pools)} pools")

    out = {
        "source": "OKX Onchain OS, official onchainos CLI v4.4.10, authenticated",
        "chain_id": int(CHAIN_ID),
        "chain_name": "X Layer",
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "tokens": rows,
        "candles": series,
        "defi": {"earn": earn, "lending": lending, "pools": pools},
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)
    print(f"\nwrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
