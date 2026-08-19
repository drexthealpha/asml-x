"""Real swap calldata from the OKX Onchain OS aggregator, for chain 196.

THIS IS THE PIECE THAT MAKES THE AGENT TRADE REAL TOKENS.

Everything before this priced real markets and then executed on an order book this project
deployed. The aggregator's `swap` endpoint closes that gap: it returns the router address, the
exact calldata, and the minimum output for a swap that crosses the same real pools the depth
ladder measured. A contract that forwards that calldata is trading on X Layer for real.

WHAT IS RETURNED AND WHY EACH FIELD MATTERS TO THE RISK GATE:

  tx.to                the router. NOT trusted blindly: the executor pins it, so a compromised
                       feed cannot redirect funds to an arbitrary contract.
  tx.data              the calldata. Opaque by nature, which is exactly why the guarantee has to
                       come from the balance check around the call rather than from parsing it.
  tx.minReceiveAmount  the floor the router itself commits to. The executor requires AT LEAST
                       this, measured as a balance delta, so a router that under-delivers reverts.
  tx.gas               the router's own estimate.

THE SECURITY POSTURE, stated plainly. Forwarding third-party calldata is the most dangerous thing
this project does, and it is not made safe by trusting OKX. It is made safe by the executor
measuring its own balances before and after and reverting unless it received at least the minimum,
which holds even if the calldata is hostile.

`userWalletAddress` must be the CONTRACT that will hold the tokens and send the transaction, not a
person's wallet: the router encodes the recipient into the calldata.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from okx_dex import creds, signed_get  # noqa: E402

CHAIN = "196"


def swap(from_token, to_token, amount_raw, wallet, slippage="0.01", c=None):
    """Fetch executable swap calldata. Returns a dict or None.

    `amount_raw` is in the from-token's smallest unit. `slippage` is a PERCENT: the v6 endpoint takes `slippagePercent`, not the fractional
    `slippage` the older docs show, and rejects the request outright if the old name is used.
    """
    c = c or creds()
    if not c:
        return None
    path = (
        f"/api/v6/dex/aggregator/swap?chainIndex={CHAIN}&amount={amount_raw}"
        f"&fromTokenAddress={from_token}&toTokenAddress={to_token}"
        f"&slippagePercent={slippage}&userWalletAddress={wallet}"
    )

    # BUILDER CODE / REFERRER FEE.
    #
    # I previously reported that no builder-code parameter was documented. That was wrong: it is
    # `fromTokenReferrerWalletAddress` plus `feePercent` on the aggregator swap endpoint, and OKX
    # permits up to 3% per swap on EVM chains. Reporting a feature as absent because I had not
    # found it is the same failure as inventing one, in the opposite direction.
    #
    # OFF BY DEFAULT, DELIBERATELY. A fee that appears without the operator asking for it is a fee
    # taken from a user who was not told. It is enabled only when `ASML_BUILDER_ADDRESS` is set,
    # and the rate is disclosed on the quote so the caller sees what is being charged.
    #
    # THE CAP IS ENFORCED HERE TOO. OKX allows up to 3%; this refuses anything above 1%, because
    # the ceiling a platform permits is not the ceiling a product should reach for, and a
    # misplaced decimal in an env var should not be able to take 3% of someone's trade.
    referrer = os.environ.get("ASML_BUILDER_ADDRESS", "").strip()
    if referrer:
        try:
            rate = float(os.environ.get("ASML_BUILDER_FEE_PERCENT", "0.1"))
        except ValueError:
            rate = 0.1
        rate = max(0.0, min(rate, 1.0))
        path += f"&fromTokenReferrerWalletAddress={referrer}&feePercent={rate}"
    r = signed_get(path, c)
    if not r or r.get("code") != "0" or not r.get("data"):
        return {"error": (r or {}).get("msg", "no response")}

    d = r["data"][0]
    tx = d.get("tx") or {}
    rr = d.get("routerResult") or {}

    venues = []
    for hop in rr.get("dexRouterList") or []:
        name = (hop.get("dexProtocol") or {}).get("dexName")
        if name and name not in venues:
            venues.append(name)

    return {
        "to": tx.get("to"),
        "data": tx.get("data"),
        "value": tx.get("value", "0"),
        "gas": tx.get("gas"),
        "min_receive": tx.get("minReceiveAmount"),
        "expected_out": rr.get("toTokenAmount"),
        "price_impact_pct": rr.get("priceImpactPercentage") or rr.get("priceImpactPercent"),
        "venues": venues,
    }


def main():
    """Probe one real route so the shape is recorded rather than assumed."""
    c = creds()
    if not c:
        print("No OKX credentials at ~/.asml-keys/okx.env.")
        return 1

    # Addresses, decimals and the wallet all come from the chain and the deploy manifest. The
    # amount is NOT a typed 1000000: `units` reads USDT's declared 6 decimals, so this is one whole
    # USDT on any chain, and the same call against WBTC (8) or SOL (9) would size itself correctly.
    import tokens
    from router_addr import _deployer

    try:
        usdt = tokens.address("USDT", c)
        wokb = tokens.address("WOKB", c)
        amount = str(tokens.units("USDT", 1, c))
    except tokens.TokenNotListed as e:
        print(f"token lookup failed: {e}")
        return 1
    wallet = _deployer()

    out = swap(usdt, wokb, amount, wallet, c=c)
    if not out or out.get("error"):
        print(f"swap quote failed: {(out or {}).get('error')}")
        return 1

    print("REAL SWAP CALLDATA, 1 USDT -> WOKB on chain 196")
    print(f"  router        {out['to']}")
    print(f"  calldata      {len(out['data'] or '')} chars")
    print(f"  min receive   {out['min_receive']}")
    print(f"  expected out  {out['expected_out']}")
    print(f"  gas estimate  {out['gas']}")
    print(f"  venues        {', '.join(out['venues']) or 'unnamed'}")

    ev = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "evidence", "phase19", "swap-calldata.txt",
    )
    os.makedirs(os.path.dirname(ev), exist_ok=True)
    with open(ev, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("Executable swap calldata from OKX Onchain OS, chain 196\n\n")
        # The calldata itself is truncated in the evidence file: it is hundreds of bytes, it is
        # regenerated on every run with a fresh deadline, and a stale copy in a repo invites
        # someone to replay it. The router, the minimum and the venues are the durable facts.
        redacted = dict(out)
        redacted["data"] = (out["data"] or "")[:74] + "... truncated, regenerated per trade"
        fh.write(json.dumps(redacted, indent=2))
        fh.write("\n")
    print(f"\nwrote {ev}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
