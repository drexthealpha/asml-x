"""Every Onchain OS surface, through the OFFICIAL CLI, in one file.

WHY THIS REPLACES THE HAND-ROLLED CLIENTS. `okx_dex.py` and friends re-implemented OKX's HMAC
signing, endpoint paths and error handling by hand. That worked, and it also meant every new
surface cost another hand-written signer. The official `onchainos` CLI already covers all of it and
is maintained by OKX, so the signing, retries, DoH fallback and quota handling stop being this
project's problem.

WHAT THE CLI UNLOCKED that the hand-rolled path never reached:

  market index          real BTC/ETH reference prices, aggregated across sources
  market kline          OHLC without scraping the v5 public API
  market portfolio-*    REAL wallet PnL, win rate, trading stats
  defi search/detail    live Aave V3 on X Layer, APY and TVL
  signal                smart money and whale tracking
  social                news and sentiment
  security              honeypot, contract and transaction scanning
  token                 holders, liquidity, risk metadata

THE CREDENTIAL BUG WORTH RECORDING. The CLI reads `OKX_SECRET_KEY`; this project's env file has
`OKX_SECRET`. With the name unmapped the CLI does not error, it silently drops to anonymous mode
and returns thin data. That is indistinguishable from "the API has nothing to say", which is the
worst kind of failure. `scripts/oos.sh` maps the names and every call goes through it.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OOS = os.path.join(REPO, "scripts", "oos.sh")
OUT_DIR = os.path.join(REPO, "ui-v2", "public", "data")

CHAIN = "xlayer"


def oos(*args, timeout=90):
    """Run one CLI command and return its parsed JSON, or None.

    The CLI prints progress lines (DoH checksum fetches, downloads) before its JSON, so the parser
    starts at the first brace rather than assuming the whole of stdout is JSON.
    """
    try:
        r = subprocess.run(
            ["bash", OOS, *[str(a) for a in args]],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None
    out = r.stdout
    i = out.find("{")
    if i < 0:
        return None
    try:
        d = json.loads(out[i:])
    except json.JSONDecodeError:
        return None
    return d if d.get("ok") else None


def data(d, *path, default=None):
    """Walk a nested response safely. Absence returns the default, never raises."""
    cur = (d or {}).get("data")
    for p in path:
        if cur is None:
            return default
        cur = cur.get(p) if isinstance(cur, dict) else None
    return default if cur is None else cur


def token_price(address):
    d = oos("--chain", CHAIN, "market", "price", "--address", address)
    rows = (d or {}).get("data") or []
    return rows[0].get("price") if rows else None


def index_price(address=""):
    """Aggregated index price. The real reference the RWA divergence check should compare against."""
    d = oos("--chain", CHAIN, "market", "index", "--address", address)
    rows = (d or {}).get("data") or []
    return rows[0].get("price") if rows else None


def defi_products(tokens="USDT,USDC,OKB", group="SINGLE_EARN"):
    """Live yield products. Real APY and TVL, not a projection."""
    d = oos("defi", "search", "--chain", CHAIN, "--token", tokens, "--product-group", group)
    raw = (d or {}).get("data") or {}
    lst = raw.get("investments") or raw.get("list") or []
    out = []
    for p in lst:
        out.append({
            "platform": p.get("platformName"),
            "name": p.get("investmentName") or p.get("platformName"),
            "apy": p.get("rate"),
            "tvl": p.get("tvl"),
            "id": p.get("investmentId"),
            "type": p.get("investmentType"),
        })
    return out


def wallet_pnl(address):
    """REAL profit and loss for an address, from OKX rather than from our own journal."""
    d = oos("--chain", CHAIN, "market", "portfolio-overview", "--address", address)
    return (d or {}).get("data")


def token_security(address):
    """Honeypot and contract risk, from OKX's own scanner."""
    d = oos("--chain", CHAIN, "security", "token-scan", "--address", address)
    return (d or {}).get("data")


def main():
    print("Onchain OS, via the official CLI")

    out = {
        "source": "onchainos CLI v4.4.10, authenticated with the project API key",
        "chain": CHAIN,
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    wokb = "0xe538905cf8410324e03a5a23c1c177a474d59b2b"
    p = token_price(wokb)
    print(f"  WOKB price        {p}")
    out["wokb_price"] = p

    idx = index_price(wokb)
    print(f"  WOKB index        {idx}")
    out["wokb_index"] = idx

    defi = defi_products()
    print(f"  DeFi products     {len(defi)}")
    for d in defi[:5]:
        print(f"    {d['platform']:<28} APY {d['apy']}  TVL {d['tvl']}")
    out["defi"] = defi

    lending = defi_products(group="LENDING")
    print(f"  Lending products  {len(lending)}")
    out["lending"] = lending

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "onchainos.json")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)
    print(f"\nwrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
