"""Real X Layer liquidity from OKX Onchain OS, written as a feed the agent and the UI both read.

THIS IS THE FILE THAT KILLS "MOCK ORDER BOOK AS SOURCE OF TRUTH".

What it proves, from chain 196 through OKX's aggregator, all of it live:

  - REAL TOKENS. USDT, USDC, ETH, SOL, DAI, crvUSD, USDG and OKB, with their real mainnet contract
    addresses and decimals. Not tBASE and tQUOTE.
  - REAL VENUES. The router breakdown names the pools an order would actually cross, and on X Layer
    those are Uniswap V3 and Uniswap V4. An earlier document in this repo concluded no Uniswap
    existed at any canonical address on the chain we probed; that was true of TESTNET 1952 and is
    not true of MAINNET 196.
  - REAL PRICES. Per-token unit prices from the aggregator, not from a book we posted ourselves.
  - REAL RISK FLAGS. `isHoneyPot` and `taxRate` per token, which is exactly the kind of input a risk
    gate should refuse on and which a seeded venue can never produce.

WHAT IS STILL OURS, stated so the claim stays exact: settlement of the agent's own trades happens on
this project's venue contract, which is labelled a self-deployed stand-in wherever it appears. This
feed makes the agent's VIEW of the market real. Routing execution through the aggregator is the next
step and is not claimed here.

Credentials live at ~/.asml-keys/okx.env, outside the repo. Nothing is printed or written from them.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from okx_dex import creds, signed_get  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "ui-v2", "public", "data", "liquidity.json")
EVIDENCE = os.path.join(REPO, "evidence", "phase19", "xlayer-liquidity.txt")

CHAIN = "196"
# DISCOVERED, never typed. See tokens.py for why a literal address is indistinguishable from
# mock data once the chain moves. `units` uses the decimals the CONTRACT declares: WOKB is 18 but
# WBTC is 8 and SOL is 9, so a shared 1e18 constant was silently wrong for most of the chain.
import tokens as tokenlist  # aliased: `tokens` is already a local in main() for the API response


def main():
    c = creds()
    if not c:
        print(f"no credentials at ~/.asml-keys/okx.env; nothing written")
        return 2

    # Addresses and the unit size are resolved from the chain's own listing. One whole WOKB is
    # 10**18 only because WOKB declares 18 decimals; the same line against WBTC would need 10**8.
    try:
        wokb = tokenlist.address("WOKB", c)
        usdt = tokenlist.address("USDT", c)
        one_wokb = tokenlist.units("WOKB", 1, c)
    except tokenlist.TokenNotListed as e:
        print(f"chain {CHAIN} token lookup failed: {e}. Nothing written.")
        return 1

    tokens = signed_get(f"/api/v6/dex/aggregator/all-tokens?chainIndex={CHAIN}", c)
    quote = signed_get(
        f"/api/v6/dex/aggregator/quote?chainIndex={CHAIN}&amount={one_wokb}"
        f"&fromTokenAddress={wokb}&toTokenAddress={usdt}",
        c,
    )

    if not tokens or tokens.get("code") != "0" or not quote or quote.get("code") != "0":
        # A failed fetch writes nothing. A stale liquidity file is worse than an absent one,
        # because the agent would price against a market that has moved.
        print("OKX DEX fetch failed; feed not written")
        return 1

    tok_rows = []
    for t in tokens.get("data") or []:
        tok_rows.append(
            {
                "symbol": t.get("tokenSymbol"),
                "address": t.get("tokenContractAddress"),
                "decimals": t.get("decimals"),
            }
        )

    q = (quote.get("data") or [{}])[0]

    # The venues an order would actually cross, and how the aggregator splits across them.
    venues, seen = [], set()
    for leg in q.get("dexRouterList") or []:
        proto = leg.get("dexProtocol") or {}
        name = proto.get("dexName")
        if name and name not in seen:
            seen.add(name)
            venues.append({"venue": name, "percent": proto.get("percent")})

    # Per-token risk flags. A honeypot or a transfer tax is a reason to refuse, and this is the only
    # place in the system that can know about either.
    flags = []
    for leg in q.get("dexRouterList") or []:
        for side in ("fromToken", "toToken"):
            t = leg.get(side) or {}
            sym = t.get("tokenSymbol")
            if sym and not any(f["symbol"] == sym for f in flags):
                flags.append(
                    {
                        "symbol": sym,
                        "unit_price_usd": t.get("tokenUnitPrice"),
                        "is_honeypot": bool(t.get("isHoneyPot")),
                        "tax_rate": t.get("taxRate", "0"),
                    }
                )

    out = {
        "source": "OKX Onchain OS DEX aggregator v6, authenticated",
        "chain": CHAIN,
        "chain_name": "X Layer mainnet",
        "verified_by": "python3 scripts/okx_dex_feed.py",
        "context_slot": q.get("contextSlot"),
        "token_count": len(tok_rows),
        "tokens": tok_rows,
        "reference_pair": "WOKB/USDT",
        "venues": venues,
        "token_risk": flags,
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)

    os.makedirs(os.path.dirname(EVIDENCE), exist_ok=True)
    with open(EVIDENCE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("Real X Layer mainnet liquidity, via OKX Onchain OS DEX aggregator v6\n")
        fh.write(f"chain {CHAIN}, block context {q.get('contextSlot')}\n\n")
        fh.write(f"tokens available: {len(tok_rows)}\n")
        for t in tok_rows[:12]:
            fh.write(f"  {t['symbol']:10} {t['address']}\n")
        fh.write("\nvenues an order actually crosses:\n")
        for v in venues:
            fh.write(f"  {v['venue']}  {v['percent']}%\n")
        fh.write("\nper-token risk flags:\n")
        for f in flags:
            fh.write(
                f"  {f['symbol']:8} ${f['unit_price_usd']:>10}  honeypot={f['is_honeypot']}  tax={f['tax_rate']}\n"
            )
        fh.write("\nThis is real mainnet liquidity. Execution of the agent's own trades still\n")
        fh.write("settles on this project's venue contract, labelled a stand-in everywhere.\n")

    print(f"chain {CHAIN}: {len(tok_rows)} real tokens")
    print(f"venues: {', '.join(v['venue'] for v in venues)}")
    for f in flags:
        print(f"  {f['symbol']:8} ${f['unit_price_usd']:>10} honeypot={f['is_honeypot']} tax={f['tax_rate']}")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
