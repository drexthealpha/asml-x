"""THE ONLY PLACE A TOKEN ADDRESS IS OBTAINED. Nothing in this repo may type one.

WHY THIS FILE EXISTS. Six scripts each carried their own literal for WOKB and USDT, copied by
hand out of a listing. Every one of them was a snapshot of a chain that moves, and they fail
silently: a token migrating to a new contract, or a symbol resolving to a bridged variant, leaves
the product confidently quoting, routing and DISPLAYING the wrong asset with nothing going red.
That is indistinguishable from mock data, because the number on screen stops corresponding to the
thing it names.

The aggregator's `all-tokens` endpoint is the chain's own answer to "what is listed here". Every
address in this project now comes from it, at run time, every run.

EXACT SYMBOL MATCH, never a substring. X Layer lists both `USDT` and `USDT_Bridged`, and both
`USDC` and `USDC_Bridged`. They are different assets with different liquidity and different
issuers. A substring match would pick whichever came back first, and the failure would be
invisible until someone tried to withdraw.

DECIMALS COME FROM THE SAME RESPONSE. USDT is 6 decimals on X Layer and most of this codebase
assumed 18. An assumed exponent is a hardcoded number in the arithmetic itself: it turns a real
10 USDT balance into 0.00000000000001 on screen, which reads as the money having vanished.

RAISES rather than falling back. There is no remembered address to fall back TO, by design.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from okx_dex import creds, signed_get  # noqa: E402

CHAIN = "196"

_cache = None


class TokenNotListed(RuntimeError):
    """A symbol this project expects is not listed on the chain. A real event, never swallowed."""


def all_tokens(c=None):
    """The chain's full token list as {symbol: {address, decimals, name}}.

    Cached for the life of the process only. A long-lived process would still see a stale list, so
    nothing here is cached to disk: a file cache is how a "discovered" address quietly becomes a
    hardcoded one again.
    """
    global _cache
    if _cache is not None:
        return _cache

    c = c or creds()
    if not c:
        raise TokenNotListed("No OKX credentials at ~/.asml-keys/okx.env")

    r = signed_get(f"/api/v6/dex/aggregator/all-tokens?chainIndex={CHAIN}", c)
    if not r or r.get("code") != "0":
        raise TokenNotListed(f"could not read the chain token list: {(r or {}).get('msg')}")

    out = {}
    for t in r.get("data", []):
        sym = (t.get("tokenSymbol") or "").strip()
        addr = t.get("tokenContractAddress")
        if not sym or not addr or sym in out:
            continue
        try:
            dec = int(t.get("decimals", 18))
        except (TypeError, ValueError):
            continue
        out[sym] = {
            "address": addr,
            "decimals": dec,
            "name": (t.get("tokenName") or "").strip(),
        }
    if not out:
        raise TokenNotListed("the chain token list came back empty")
    _cache = out
    return out


def address(symbol, c=None):
    """Contract address for an exact symbol. Raises if the chain does not list it."""
    t = all_tokens(c).get(symbol)
    if not t:
        raise TokenNotListed(f"chain {CHAIN} does not list {symbol}")
    return t["address"]


def decimals(symbol, c=None):
    """Decimals as the CONTRACT declares them, never assumed."""
    t = all_tokens(c).get(symbol)
    if not t:
        raise TokenNotListed(f"chain {CHAIN} does not list {symbol}")
    return t["decimals"]


def units(symbol, whole, c=None):
    """Convert a whole-token amount to the smallest unit, using the real decimals.

    Integer arithmetic. `whole` may be an int or a decimal string; floats are rejected, because a
    float amount of money is a rounding error waiting to be signed.
    """
    if isinstance(whole, float):
        raise TypeError("pass an int or a decimal string, never a float, for a token amount")
    d = decimals(symbol, c)
    s = str(whole)
    ipart, _, fpart = s.partition(".")
    fpart = (fpart + "0" * d)[:d]
    return int(ipart) * (10**d) + (int(fpart) if fpart else 0)


if __name__ == "__main__":
    for sym, t in sorted(all_tokens().items()):
        print(f"  {sym:<14} {t['address']}  {t['decimals']:>2} dec  {t['name']}")
