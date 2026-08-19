"""Emit executable swap calldata as JSON, for submit-swap.sh.

Thin on purpose. Everything real lives in okx_swap.py and tokens.py; this exists because
`submit-swap.sh` needs one JSON object on stdout, and because CLAUDE.md E4 makes building that
object inside a `wsl -- bash -c` invocation unreliable.

Usage: swap_calldata.py <from_symbol> <to_symbol> <amount_whole> <recipient>

`amount_whole` is a whole-token amount as an integer or decimal STRING, never a float. It is
converted using the decimals the token contract declares, so "1" means one whole token whether that
is 10**18 (WOKB), 10**8 (WBTC), 10**9 (SOL) or 10**6 (USDT). A shared 1e18 constant was wrong for
most tokens on this chain.

Exits non-zero with a message on stderr if the pair cannot be routed. A pair the aggregator
declines is a real finding: it means the pools are too thin to trade the size, and the correct
response is to not trade, not to substitute a number.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tokens  # noqa: E402
from okx_dex import creds  # noqa: E402
from okx_swap import swap  # noqa: E402


def main():
    if len(sys.argv) < 5:
        print("usage: swap_calldata.py <from> <to> <amount_whole> <recipient>", file=sys.stderr)
        return 2
    from_sym, to_sym, amount_whole, recipient = sys.argv[1:5]

    c = creds()
    if not c:
        print("no OKX credentials at ~/.asml-keys/okx.env", file=sys.stderr)
        return 1

    try:
        from_addr = tokens.address(from_sym, c)
        to_addr = tokens.address(to_sym, c)
        amount_raw = tokens.units(from_sym, amount_whole, c)
    except (tokens.TokenNotListed, TypeError, ValueError) as e:
        print(str(e), file=sys.stderr)
        return 1

    out = swap(from_addr, to_addr, str(amount_raw), recipient, c=c)
    if not out or out.get("error"):
        print((out or {}).get("error", "no response"), file=sys.stderr)
        return 1
    if not out.get("data") or not out.get("min_receive"):
        # A quote with no calldata or no floor is not executable, and passing a zero minimum to the
        # contract would disable the only check standing between this and a drained balance.
        print("the aggregator returned no calldata or no minimum", file=sys.stderr)
        return 1

    out["from_address"] = from_addr
    out["to_address"] = to_addr
    out["amount_raw"] = str(amount_raw)
    json.dump(out, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
