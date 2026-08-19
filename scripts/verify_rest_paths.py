"""Probe every REST path the Vercel functions need, and record which ones actually answer.

WHY. The functions were written from memory of what the CLI does. `market/price` is a POST with a
JSON body; the function called it as a GET with query parameters, got nothing back, and rendered
"no price" for tokens that have one. Nothing errored. The deployed site showed 0 priced
instruments out of 8 and looked like a dead market.

A path that returns nothing is indistinguishable from an asset with no price. So no path goes into
a serverless function until it appears in this file's output next to real data.

Prints a table of path, method, and what came back. Exits non-zero if anything a function depends
on returns nothing.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from okx_dex import creds, signed_get, signed_post  # noqa: E402
import tokens as tokenlist  # noqa: E402

CHAIN = "196"


def show(label, method, path, data, required=True):
    if isinstance(data, list):
        state = f"{len(data)} rows"
        ok = len(data) > 0
    elif isinstance(data, dict):
        state = ", ".join(list(data.keys())[:4])
        ok = bool(data)
    else:
        state = "NOTHING"
        ok = False
    flag = "" if ok else ("   <-- REQUIRED, RETURNS NOTHING" if required else "   (optional)")
    print(f"  {method:<5} {label:<22} {state}{flag}")
    return ok or not required


def main():
    c = creds()
    if not c:
        print("no credentials")
        return 1

    try:
        listed = tokenlist.all_tokens(c)
    except tokenlist.TokenNotListed as e:
        print(f"token list unavailable: {e}")
        return 1

    wokb = listed["WOKB"]["address"]
    usdt = listed["USDT"]["address"]
    ok = True

    print("Paths the Vercel functions depend on\n")

    # ---- token list
    d = signed_get(f"/api/v6/dex/aggregator/all-tokens?chainIndex={CHAIN}", c)
    ok &= show("all-tokens", "GET", "aggregator/all-tokens", (d or {}).get("data"))

    # ---- price. THE ONE THAT WAS WRONG. POST with a JSON body, not GET with query parameters.
    d = signed_post(
        "/api/v6/dex/market/price",
        [{"chainIndex": CHAIN, "tokenContractAddress": wokb}],
        c,
    )
    ok &= show("market/price", "POST", "market/price", (d or {}).get("data"))

    # The GET form, recorded so the wrong shape is on the record rather than in a function.
    d = signed_get(
        f"/api/v6/dex/market/price?chainIndex={CHAIN}&tokenContractAddress={wokb}", c
    )
    show("market/price AS GET", "GET", "market/price", (d or {}).get("data"), required=False)

    # ---- index price
    for path in (
        f"/api/v6/dex/market/index-price?chainIndex={CHAIN}&tokenContractAddress={wokb}",
        f"/api/v6/dex/index-price?chainIndex={CHAIN}&tokenContractAddress={wokb}",
    ):
        d = signed_get(path, c)
        label = path.split("?")[0].replace("/api/v6/dex/", "")
        if show(label, "GET", path, (d or {}).get("data"), required=False):
            if (d or {}).get("data"):
                print(f"        ^ this is the working index path")

    # index-price as POST, since price is
    d = signed_post(
        "/api/v6/dex/market/index-price",
        [{"chainIndex": CHAIN, "tokenContractAddress": wokb}],
        c,
    )
    show("market/index-price", "POST", "market/index-price", (d or {}).get("data"), required=False)

    # ---- price info
    for path in (
        f"/api/v6/dex/market/token/price-info?chainIndex={CHAIN}&tokenContractAddress={wokb}",
        f"/api/v6/dex/market/price-info?chainIndex={CHAIN}&tokenContractAddress={wokb}",
    ):
        d = signed_get(path, c)
        show(path.split("?")[0].replace("/api/v6/dex/", ""), "GET", path,
             (d or {}).get("data"), required=False)

    d = signed_post(
        "/api/v6/dex/market/price-info",
        [{"chainIndex": CHAIN, "tokenContractAddress": wokb}],
        c,
    )
    show("market/price-info", "POST", "market/price-info", (d or {}).get("data"), required=False)

    # ---- quote
    one = tokenlist.units("WOKB", 1, c)
    d = signed_get(
        f"/api/v6/dex/aggregator/quote?chainIndex={CHAIN}&amount={one}"
        f"&fromTokenAddress={wokb}&toTokenAddress={usdt}",
        c,
    )
    ok &= show("aggregator/quote", "GET", "aggregator/quote", (d or {}).get("data"))

    # ---- defi
    for path in (
        f"/api/v6/dex/defi/explore/product/list?chainIndex={CHAIN}&productGroup=SINGLE_EARN",
        f"/api/v6/dex/defi/product/list?chainIndex={CHAIN}&productGroup=SINGLE_EARN",
    ):
        d = signed_get(path, c)
        show(path.split("?")[0].replace("/api/v6/dex/", ""), "GET", path,
             (d or {}).get("data"), required=False)

    print()
    if not ok:
        print("GATE: FAIL  a path a function depends on returns nothing")
        return 1
    print("GATE: PASS  every required path returns data")
    return 0


if __name__ == "__main__":
    sys.exit(main())
