"""Search every OKX surface for tokenized real-world assets on X Layer.

WHY THIS EXISTS. I twice reported that X Layer has no tokenized gold, silver or equity index. That
was based on ONE endpoint, `aggregator/all-tokens`, which returns the aggregator's curated list.
The aggregator also exposes a SEARCH endpoint over a much larger universe, and the market API has
its own. Neither was checked before the claim was made.

"I looked in one place and found nothing" is a different statement from "it does not exist", and
reporting the second while having established only the first is the same error as inventing a
feature, in the opposite direction. It has now happened twice in this project: once with builder
codes, once here.

WHAT COUNTS AS A REAL-WORLD ASSET, and this matters because the search will return names that look
like one and are not:
  BACKED     something outside the chain is held against it, and someone is accountable for that
  REDEEMABLE or at least priced against the thing it claims to represent
A token called "TSLA" with no issuer, no attestation and $300 of liquidity is a meme with a
ticker. Naming it a real-world asset on a product screen would be worse than showing nothing.
"""
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OOS = os.path.join(REPO, "scripts", "oos.sh")
CHAIN = "196"

# Words that appear in the name or symbol of an instrument backed by something real.
RWA_HINTS = [
    "gold", "xau", "paxg", "xaut", "silver", "xag", "platinum",
    "treasury", "bill", "bond", "yield", "note",
    "stock", "equity", "share", "index", "nasdaq", "s&p", "spx",
    "oil", "wti", "brent", "commodity",
    "estate", "property", "reit",
    "usd", "eur", "gbp", "jpy",
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


def looks_rwa(symbol, name):
    blob = f"{symbol} {name}".lower()
    return [h for h in RWA_HINTS if h in blob]


def cmd_list():
    """Every token the aggregator lists, flagged for RWA-sounding names."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import tokens

    try:
        listed = tokens.all_tokens()
    except tokens.TokenNotListed as e:
        print(f"  token list unavailable: {e}")
        return

    print(f"  {len(listed)} tokens listed by the aggregator")
    for sym, t in sorted(listed.items()):
        hits = looks_rwa(sym, t["name"])
        mark = "  <-- RWA-sounding" if hits else ""
        print(f"    {sym:<16} {t['name']:<28}{mark}")


def cmd_search(query):
    """The SEARCH surface. This is the one that was never checked."""
    rows = oos("--chain", "xlayer", "token", "search", "--query", query, "--chains", CHAIN, "--limit", "50")
    if not rows:
        print(f"  {query:<14} no results")
        return

    keep = []
    for t in rows if isinstance(rows, list) else []:
        sym = (t.get("tokenSymbol") or t.get("symbol") or "").strip()
        name = (t.get("tokenName") or t.get("name") or "").strip()
        # The search is cross-chain, so anything not on 196 is irrelevant here.
        idx = str(t.get("chainIndex") or t.get("chainId") or "")
        if idx and idx != CHAIN:
            continue
        keep.append((sym, name, t.get("tokenContractAddress") or ""))

    if not keep:
        print(f"  {query:<14} nothing on chain {CHAIN}")
        return

    print(f"  {query:<14} {len(keep)} on chain {CHAIN}")
    for sym, name, addr in keep[:10]:
        print(f"      {sym:<14} {name:<30} {addr}")


def cmd_hot():
    rows = oos("--chain", "xlayer", "token", "hot-tokens")
    if not rows:
        print("  no hot-token data returned")
        return
    for t in (rows if isinstance(rows, list) else [])[:20]:
        sym = (t.get("tokenSymbol") or "").strip()
        name = (t.get("tokenName") or "").strip()
        hits = looks_rwa(sym, name)
        mark = "  <-- RWA-sounding" if hits else ""
        print(f"    {sym:<16} {name:<28}{mark}")


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "list"
    if what == "list":
        cmd_list()
    elif what == "search":
        cmd_search(sys.argv[2] if len(sys.argv) > 2 else "gold")
    elif what == "hot":
        cmd_hot()
