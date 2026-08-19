"""Market intelligence: what informed money is doing, and what the market is saying.

WHAT THIS ADDS THAT PRICE ALONE CANNOT. A price tells you where the market is. These tell you
something about WHY, and they are inputs no amount of order-book reading produces:

  signal list        wallets classified as smart money / KOL / whale, and what they just bought
  social sentiment   bullish / bearish / neutral counts across news and X, per symbol
  social news        the actual headlines, with an importance and a sentiment label

HOW THE AGENT IS ALLOWED TO USE THEM, and the limit is deliberate. Sentiment moves a CONFIDENCE
term, never a limit. The whole architecture of this project rests on limits that can only tighten
and cannot be widened by anything the agent learns or reads; a bullish news cycle that could raise
an exposure cap would be a hole straight through that guarantee. So these feed the scoring, and the
risk engine never sees them.

EVERY FIGURE IS A COUNT, NOT A SCORE. `bullishRatio` is derived from actual mention counts that
come back in the same response, so a reader can check the arithmetic. Nothing here is a proprietary
index this project invented and asked anyone to trust.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OOS = os.path.join(REPO, "scripts", "oos.sh")
OUT = os.path.join(REPO, "ui-v2", "public", "data", "intel.json")
CHAIN = "xlayer"

# The symbols this product actually lets someone trade. Not a watchlist typed for effect: every one
# of these is priced and routable on chain 196.
SYMBOLS = "BTC,ETH,OKB,USDT,USDC"


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


def sentiment():
    """Bullish / bearish / neutral counts per symbol, over the last hour."""
    d = oos("social", "sentiment-symbol", "--token-symbols", SYMBOLS)
    rows = []
    for x in (d or {}).get("details", []):
        s = x.get("sentiment") or {}
        rows.append({
            "symbol": x.get("tokenSymbol"),
            "mentions": x.get("mentionCount"),
            "news_mentions": x.get("newsMentionCount"),
            "x_mentions": x.get("xMentionCount"),
            "bullish": s.get("bullishCnt"),
            "bearish": s.get("bearishCnt"),
            "neutral": s.get("neutralCnt"),
            "bullish_ratio": s.get("bullishRatio"),
            "label": s.get("label"),
        })
    return rows, (d or {}).get("period")


def news(limit=8):
    """Headlines with their own sentiment and importance labels, as the source assigned them."""
    d = oos("social", "news-by-symbol", "--token-symbols", SYMBOLS, "--sort-by", "2")
    # `articles`, read from a real response. Not `list`, which is what the sibling endpoints use.
    items = (d or {}).get("articles") or []
    out = []
    for n in items[:limit]:
        out.append({
            "title": n.get("title"),
            "source": n.get("platformName") or n.get("source"),
            "sentiment": n.get("sentiment"),
            "importance": n.get("importance"),
            "ts": n.get("publishTime") or n.get("ts"),
            "url": n.get("url") or n.get("link"),
        })
    return out


def smart_money(min_usd=1000, limit=12):
    """What wallets classified as smart money, KOL or whale just did on this chain."""
    d = oos("signal", "list", "--chain", CHAIN, "--min-amount-usd", str(min_usd))
    rows = d if isinstance(d, list) else (d or {}).get("list") or []
    out = []
    for s in rows[:limit]:
        # FIELD NAMES READ FROM AN ACTUAL RESPONSE, not guessed. The first version looked for
        # `tokenInfo`, which does not exist; the nested object is `token`. Every field then came
        # back None and the panel would have rendered eleven blank rows while reporting eleven
        # signals: present, plausible, and empty.
        tok = s.get("token") or {}
        out.append({
            "symbol": tok.get("symbol"),
            "name": tok.get("name"),
            "address": tok.get("tokenAddress"),
            "wallets": s.get("triggerWalletCount"),
            # The API's own classification: 1 smart money, 2 KOL, 3 whale.
            "wallet_type": s.get("walletType"),
            "amount_usd": s.get("amountUsd"),
            "price": s.get("price"),
            "holders": tok.get("holders"),
            "market_cap_usd": tok.get("marketCapUsd"),
            "top10_holder_percent": tok.get("top10HolderPercent"),
            "sold_ratio_percent": s.get("soldRatioPercent"),
            "timestamp": s.get("timestamp"),
        })
    return out


def main():
    print("Market intelligence, via Onchain OS")

    sent, period = sentiment()
    for s in sent:
        print(f"  {s['symbol']:<6} {s['mentions']:>5} mentions  "
              f"{s['bullish']} bullish / {s['bearish']} bearish  → {s['label']}")

    headlines = news()
    print(f"  headlines      {len(headlines)}")

    smart = smart_money()
    print(f"  smart money    {len(smart)} signals")
    for s in smart[:4]:
        print(f"    {s['symbol']} — {s['wallets']} wallets")

    out = {
        "source": "OKX Onchain OS: social sentiment, news, smart-money signals",
        "chain_id": 196,
        "period": period,
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "sentiment": sent,
        "news": headlines,
        "smart_money": smart,
        # Stated in the data so the UI can show it. A sentiment reading next to a trading control
        # invites the assumption that it moves limits; it does not, and saying so is cheaper than
        # a reader discovering the distinction later.
        "usage_note": (
            "Sentiment and signals inform how confident the agent is. They never change the limit "
            "you set. Limits only ever move down."
        ),
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
