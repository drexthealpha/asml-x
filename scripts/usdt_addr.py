"""Resolve USDT's contract address on X Layer from the chain's own token list.

Separate from the shell script deliberately. The address must not be a literal anywhere: the
whole point of pointing the vault at a real token is that the token is not ours, so its address is
a fact about the chain and has to be read from the chain every time.

Prints the address and exits 0, or prints nothing and exits 1. `X Layer` lists more than one
dollar token whose symbol contains USDT, including `USDT_Bridged`, so the match is EXACT on the
symbol `USDT` rather than a substring: a bridged variant is a different asset with different
liquidity, and picking it by accident would be invisible until someone tried to withdraw.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from okx_dex import creds, signed_get  # noqa: E402


def main():
    c = creds()
    if not c:
        return 1
    r = signed_get("/api/v6/dex/aggregator/all-tokens?chainIndex=196", c)
    if not r or r.get("code") != "0":
        return 1
    for t in r.get("data", []):
        if (t.get("tokenSymbol") or "").strip() == "USDT":
            addr = t.get("tokenContractAddress")
            if addr:
                print(addr)
                return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
