"""Read the OKX Onchain OS router address off a LIVE swap quote for chain 196.

Not a constant, deliberately. The router is OKX's contract; its address is a fact about the chain,
and this repo has no standing to assert it. Reading it from a quote also proves the endpoint works
before a deploy spends anything, which is the cheapest possible preflight.

Prints the address and exits 0, or prints nothing and exits 1.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from okx_dex import creds  # noqa: E402
from okx_swap import swap  # noqa: E402

import tokens  # noqa: E402


def _deployer():
    """The deployer address, from the mainnet manifest the deploy scripts write.

    Was a literal. It is recorded in `deployments-mainnet.json` by the deploy that created it, so
    reading it there means a key rotation cannot leave a stale address quoted here.
    """
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(repo, "deployments-mainnet.json"), encoding="utf-8") as fh:
        return json.load(fh)["deployer"]


def main():
    c = creds()
    if not c:
        return 1
    # One whole USDT, sized from the decimals the CONTRACT declares rather than a typed 1000000.
    # Any size returns the same router; the smallest is used so the quote is cheap for OKX to
    # compute and cannot be mistaken for an intent to trade.
    try:
        usdt = tokens.address("USDT", c)
        wokb = tokens.address("WOKB", c)
        one = tokens.units("USDT", 1, c)
    except tokens.TokenNotListed:
        return 1
    # The wallet is the DEPLOYER, read from the same place every script reads it, not typed here.
    wallet = os.environ.get("DEPLOYER_ADDRESS") or _deployer()
    out = swap(usdt, wokb, str(one), wallet, c=c)
    if not out or out.get("error") or not out.get("to"):
        return 1
    print(out["to"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
