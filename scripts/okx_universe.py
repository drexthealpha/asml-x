"""Every token tradable on X Layer, with a live price and a live route. One file, one fetch.

WHAT THIS IS FOR. The product is "trade real tokens on X Layer, safely". That needs one thing the
old feeds never produced: the actual list of what can be traded, priced, right now. Not a curated
subset, not a hand-picked pair, not a menu written into a source file. Everything the chain lists.

WHAT EACH FIELD IS AND WHERE IT COMES FROM, because a price with no provenance is decoration:

  symbol, name, address, decimals   GET  /aggregator/all-tokens        the chain's own listing
  price                             POST /market/price                 signed, live
  routable                          GET  /aggregator/quote             can it actually be traded
  venues                            the same quote                     which pools it crosses

NOTHING IS DEFAULTED. A token with no price gets `price: null` and is shown as unpriced, never as
zero. A token the router declines is marked not routable and the reason is carried through. Both
are real findings: an unpriced or unroutable token is one a user must not be invited to trade.

NO SYMBOL LIST LIVES HERE. Adding a token to X Layer makes it appear in this file with no code
change, which is the only version of "supports every token" that is true.
"""
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tokens  # noqa: E402
from okx_dex import creds, signed_get, signed_post  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "ui-v2", "public", "data", "universe.json")
CHAIN = "196"

# The quote asset every price is expressed against, resolved from the chain like everything else.
QUOTE = "USDT"

# Tokens whose price the market endpoint may not carry are still probed for routability, because a
# token that routes is tradable even if the price feed has no entry for it.
BATCH = 20


def main():
    c = creds()
    if not c:
        print("no OKX credentials; nothing written")
        return 1

    try:
        listed = tokens.all_tokens(c)
        quote_addr = tokens.address(QUOTE, c)
    except tokens.TokenNotListed as e:
        print(f"token list unavailable: {e}")
        return 1

    print(f"chain {CHAIN} lists {len(listed)} tokens")

    # ---- prices, in batches, from the signed market endpoint
    prices = {}
    items = list(listed.items())
    for i in range(0, len(items), BATCH):
        body = [
            {"chainIndex": CHAIN, "tokenContractAddress": t["address"]}
            for _, t in items[i : i + BATCH]
        ]
        r = signed_post("/api/v6/dex/market/price", body, c)
        if r and r.get("code") == "0":
            for d in r.get("data", []):
                if d.get("price"):
                    prices[d["tokenContractAddress"].lower()] = d["price"]

    rows = []
    for symbol, t in sorted(listed.items()):
        addr = t["address"]
        price = prices.get(addr.lower())

        # ---- routability, one real quote per token
        routable, venues, note = False, [], None
        if addr.lower() == quote_addr.lower():
            routable, note = True, "this is the quote asset"
        else:
            one = 10 ** t["decimals"]
            q = signed_get(
                f"/api/v6/dex/aggregator/quote?chainIndex={CHAIN}&amount={one}"
                f"&fromTokenAddress={addr}&toTokenAddress={quote_addr}",
                c,
            )
            if q and q.get("code") == "0" and q.get("data"):
                routable = True
                for hop in q["data"][0].get("dexRouterList") or []:
                    n = (hop.get("dexProtocol") or {}).get("dexName")
                    if n and n not in venues:
                        venues.append(n)
            else:
                # The router's own words. "Value difference higher than 90%" means the pools are
                # too thin to trade this token at all, which the user needs to know BEFORE they
                # pick it, not after a failed transaction.
                note = (q or {}).get("msg") or "the router did not return a route"

        rows.append({
            "symbol": symbol,
            "name": t["name"],
            "address": addr,
            "decimals": t["decimals"],
            "price": price,
            "routable": routable,
            "venues": venues,
            "note": note,
        })
        state = "priced" if price else "unpriced"
        print(f"  {symbol:<14} {state:<9} {'routable' if routable else 'NOT routable'}")

    out = {
        "source": "OKX Onchain OS, signed",
        "chain_id": int(CHAIN),
        "chain_name": "X Layer",
        "quote_symbol": QUOTE,
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "token_count": len(rows),
        "tradable_count": sum(1 for r in rows if r["routable"] and r["price"]),
        "tokens": rows,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)

    print(f"\n{out['tradable_count']} of {len(rows)} are priced AND routable")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
