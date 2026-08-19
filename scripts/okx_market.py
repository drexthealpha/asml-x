"""Real market data from OKX's public v5 market API. No API key, no simulation.

WHY THIS EXISTS. The agent's signals came from an order book this project deployed and seeded, which
is honest but is not real-world data. `docs/verified/exchangeos-mainnet.md` concluded there was no
usable OKX developer surface, and that conclusion was WRONG in an important way: it was reached
through a resolver that cannot see okx.com (E9), so every probe returned 000 (DNS failure) and was
read as "unreachable". Pinning DNS shows the opposite.

WHAT IS AND IS NOT KEYLESS, measured by scripts/205 and 206:

  www.okx.com/api/v5/market/*        200, NO key. Ticker, candles, index prices.
  web3.okx.com/api/v5/dex/*          401, "OK-ACCESS-KEY can not be empty". Needs credentials.

So the aggregator (swap routing) needs a key this project does not have, and the market data does
not. Market data is what the agent's thesis actually needs, so that is what is used, and the
distinction is stated rather than blurred.

WHAT THIS GIVES THE AGENT:
  OKB-USDT ticker   a real top of book: bid, ask, their sizes, and 24h range
  OKB-USDT candles  a real 1m series, so realized volatility is measured rather than assumed
  BTC-USD index     a real reference price, which is the RWA divergence layer's comparison feed

E9 HANDLING. okx.com does not resolve on the build machine. Ordinary DNS is tried first so this
works unchanged anywhere else (CI, a judge's laptop, a hosted deploy); the pinned IP is a fallback
for this machine only.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "ui-v2", "public", "data", "market.json")
EVIDENCE = os.path.join(REPO, "evidence", "phase19", "market-feed.txt")

BASE = "https://www.okx.com/api/v5/market"
PINNED_IP = "172.64.144.82"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36"


def fetch(path):
    """GET a public OKX market endpoint. Plain DNS first, pinned IP as an E9 fallback."""
    url = f"{BASE}/{path}"
    base_cmd = ["curl", "-sS", "--max-time", "25", "-A", UA]
    for extra in ([], ["--resolve", f"www.okx.com:443:{PINNED_IP}"]):
        try:
            r = subprocess.run(base_cmd + extra + [url], capture_output=True, text=True, timeout=40)
            if r.returncode == 0 and r.stdout.strip():
                d = json.loads(r.stdout)
                if d.get("code") == "0":
                    return d["data"]
        except Exception:
            continue
    return None


def main():
    ticker = fetch("ticker?instId=OKB-USDT")
    candles = fetch("candles?instId=OKB-USDT&bar=1m&limit=120")
    index = fetch("index-tickers?instId=BTC-USD")

    if not ticker:
        print("OKX market data unreachable. Writing nothing: a stale price is worse than no price.")
        return 1

    t = ticker[0]
    bid, ask = float(t["bidPx"]), float(t["askPx"])
    mid = (bid + ask) / 2
    spread_bps = round((ask - bid) / mid * 10_000, 2) if mid else 0

    # Realized volatility from the real candle series, not a constant. Standard deviation of 1m
    # log-ish returns expressed in basis points, computed with plain arithmetic.
    vol_bps = 0.0
    if candles and len(candles) > 2:
        closes = [float(c[4]) for c in candles][::-1]
        rets = [(closes[i] - closes[i - 1]) / closes[i - 1] for i in range(1, len(closes)) if closes[i - 1]]
        if rets:
            mean = sum(rets) / len(rets)
            var = sum((r - mean) ** 2 for r in rets) / len(rets)
            vol_bps = round((var ** 0.5) * 10_000, 2)

    out = {
        "source": "OKX public v5 market API, no key",
        "verified_by": "bash scripts/206-okx-price-post.sh",
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "pair": {
            "instId": "OKB-USDT",
            "last": t["last"],
            "bid": t["bidPx"],
            "bidSize": t["bidSz"],
            "ask": t["askPx"],
            "askSize": t["askSz"],
            "mid": f"{mid:.4f}",
            # STRINGS, not JSON numbers. The Rust risk path denies floating-point arithmetic at the
            # workspace lint level, so a JSON number would force an f64 parse on the way in. A
            # decimal string is parsed to integer micro units directly.
            "spread_bps": f"{spread_bps}",
            "high24h": t["high24h"],
            "low24h": t["low24h"],
            "vol24h": t["vol24h"],
        },
        "volatility": {
            "realized_bps_1m": f"{vol_bps}",
            "samples": len(candles) if candles else 0,
            "basis": "standard deviation of 1-minute close-to-close returns",
        },
        # THE REAL SERIES, kept so the chart plots measured prices rather than a decorative curve.
        # OKX returns newest first; reversed here so time ascends, which is what a chart library
        # expects and what a reader assumes.
        "candles": [
            {
                "t": int(c[0]) // 1000,
                "o": c[1],
                "h": c[2],
                "l": c[3],
                "c": c[4],
                "v": c[5],
            }
            for c in reversed(candles or [])
        ],
        "reference_index": (
            {"instId": "BTC-USD", "price": index[0]["idxPx"], "high24h": index[0]["high24h"]}
            if index else {"error": "index feed unavailable"}
        ),
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)

    os.makedirs(os.path.dirname(EVIDENCE), exist_ok=True)
    with open(EVIDENCE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("Live market feed from OKX public v5 API\n")
        fh.write(f"Run {out['fetched_at_utc']}\n\n")
        fh.write(json.dumps(out, indent=2))
        fh.write("\n")

    print(f"OKB-USDT  bid {out['pair']['bid']}  ask {out['pair']['ask']}  spread {spread_bps} bps")
    print(f"realized vol (1m, {out['volatility']['samples']} samples): {vol_bps} bps")
    print(f"BTC-USD index: {out['reference_index'].get('price')}")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
