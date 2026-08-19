"""Read the OKX token-approval proxy address from the live approve-transaction endpoint.

Discovered, never typed, for the same reason as router_addr.py: this is OKX's contract and its
address is a fact about the chain.

WHY IT IS A SEPARATE ADDRESS AT ALL. The aggregator calls its router, but tokens are pulled by a
distinct approval proxy. Approving the router leaves the proxy with no allowance and the swap
reverts as an uninformative `RouterCallFailed(0x0000...)`. That cost a real mainnet transaction to
discover, which is why this endpoint is now consulted rather than assumed away.

Prints the address and exits 0, or prints nothing and exits 1.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tokens  # noqa: E402
from okx_dex import creds, signed_get  # noqa: E402


def approver(c=None, symbol="WOKB"):
    """The spender to approve. Any token returns the same proxy; WOKB is used as the probe."""
    c = c or creds()
    if not c:
        return None
    addr = tokens.address(symbol, c)
    r = signed_get(
        f"/api/v6/dex/aggregator/approve-transaction?chainIndex=196"
        f"&tokenContractAddress={addr}&approveAmount=1",
        c,
    )
    if not r or r.get("code") != "0" or not r.get("data"):
        return None
    return r["data"][0].get("dexContractAddress")


def main():
    a = approver()
    if not a:
        return 1
    print(a)
    return 0


if __name__ == "__main__":
    sys.exit(main())
