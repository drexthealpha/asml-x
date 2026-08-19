"""REAL real-world assets on X Layer, priced through OKX Onchain OS.

THE HONEST FINDING FIRST, because it shapes everything below.

There is no tokenized gold, silver, or equity index on X Layer. This is not an assumption; it is
the full token list Onchain OS returns for chain 196, read and checked symbol by symbol:

  USDG USDT USDC ETH SOL OKB crvUSD DAI DMCX FB PYUSD QUICK sUSDe STONE
  USDT_Bridged USDC_Bridged USDe WBTC WOKB xBTC xBETH xOKSOL

No XAUT, no PAXG, no tokenized treasuries beyond the dollar tokens, no index products. Bolting an
off-chain gold price onto this product would put a number on the screen that the agent cannot
trade, the vault cannot hold, and the risk gate cannot enforce anything about. That is decoration,
and it is the exact failure this project is supposed to avoid.

WHAT IS ACTUALLY THERE IS STILL RWA, and it is the strongest kind for a risk product:

  PYUSD    PayPal USD. Issued by Paxos under NYDFS supervision, backed by US Treasury
           repurchase agreements and cash. A dollar token backed by government debt is a
           real-world asset by any definition a regulator uses.
  USDG     Global Dollar, reserve-backed.
  USDC     Backed by cash and short-dated US Treasuries.
  USDT     Backed by reserves including US Treasuries.
  DAI      Collateral-backed, including tokenized treasury exposure.
  crvUSD   Collateral-backed.
  USDe     Synthetic dollar, delta-hedged rather than reserve-backed. Kept BECAUSE it is
           different: it is the instrument most likely to actually break its peg, which makes it
           the one worth watching.
  sUSDe    The yield-bearing form of USDe, so it is NOT expected to sit at 1.00 and is measured
           against USDe rather than against a dollar.

WHY THIS IS THE RIGHT FEED FOR THE RWA GUARD. The RWA refusal layer exists to stop the agent
trading an instrument that has come loose from what it is supposed to be worth. For a
treasury-backed dollar token, the reference is one dollar, and the divergence is measurable to the
basis point. That is a live, real, on-chain risk on this exact chain, and the guard already
enforces a 300 bps band against it.

Every price here is a signed call to OKX Onchain OS `/api/v6/dex/market/price` for chain 196.
Nothing is fetched from a price site, nothing is hardcoded, nothing is interpolated.
"""
import json
import subprocess
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from okx_dex import creds, signed_get, signed_post  # noqa: E402

# ADDRESSES ARE DISCOVERED, NOT TYPED. An earlier version of this file carried the contract
# address of every instrument as a literal, copied out of a listing by hand. That is a hardcoded
# snapshot of a chain that changes: a token migrating to a new contract, or a new dollar token
# listing on X Layer, would leave this product confidently pricing the wrong thing or silently
# missing the right one, and nothing would fail.
#
# The aggregator's all-tokens endpoint is the chain's own answer to "what is listed here". The
# script now asks it, matches by SYMBOL, and reports any instrument the chain no longer lists
# instead of pricing a stale address.
ALL_TOKENS = f"/api/v6/dex/aggregator/all-tokens?chainIndex={{chain}}"

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "ui-v2", "public", "data", "rwa.json")
EVIDENCE = os.path.join(REPO, "evidence", "phase19", "rwa-feed.txt")

CHAIN = "196"

# The band the deployed RwaRiskGuard enforces.
#
# THIS USED TO BE THE LITERAL 300 with a comment claiming it had been read from the contract in an
# earlier phase. That comment was the tell: a number "read from the contract" once and then typed
# into a script is not read from the contract, it is remembered. If anyone tightened the band on
# chain, this product would keep telling users the old figure while the guard enforced a different
# one, and the screen would still say "enforced on chain".
#
# It is now an actual `eth_call` to the deployed guard on every run. The fallback below exists only
# so the feed still produces prices when the RPC is unreachable, and it MARKS ITSELF as unverified
# so the UI can say so rather than presenting a remembered number as a contract fact.
DIVERGENCE_FALLBACK_BPS = 300
# VERIFIED, not guessed. The first value written here was 0xd8f6bef5, invented rather than derived.
# `cast sig "maxDivergenceBps()"` gives 0xf9de4776. The wrong selector would have made every
# eth_call return 0x, the code would have fallen back to the remembered 300, and the screen would
# have said "enforced on chain" while nothing had been read from the chain at all: a silent failure
# that looks exactly like success. scripts/211-verify-selector.sh is the check, and it also reads
# the live value, currently 0x12c = 300.
RWA_GUARD_SELECTOR = "0xf9de4776"  # maxDivergenceBps(), cast sig verified


def divergence_limit_bps():
    """Read `maxDivergenceBps()` off the deployed RwaRiskGuard on chain 196.

    Returns (value, verified). `verified` False means the RPC did not answer and the value is the
    fallback, which the UI is expected to label rather than present as fact.
    """
    try:
        with open(os.path.join(REPO, "deployments-mainnet.json"), encoding="utf-8") as fh:
            m = json.load(fh)
        guard, rpc = m["rwaRiskGuard"], m["rpc"]
    except (OSError, KeyError, json.JSONDecodeError):
        return DIVERGENCE_FALLBACK_BPS, False

    payload = json.dumps({
        "jsonrpc": "2.0", "id": 1, "method": "eth_call",
        "params": [{"to": guard, "data": RWA_GUARD_SELECTOR}, "latest"],
    })
    try:
        r = subprocess.run(
            ["curl", "-sS", "--max-time", "20", "-H", "Content-Type: application/json",
             "-d", payload, rpc],
            capture_output=True, text=True, timeout=30,
        )
        result = json.loads(r.stdout).get("result")
        if result and result != "0x":
            return int(result, 16), True
    except Exception:
        pass
    return DIVERGENCE_FALLBACK_BPS, False

# Every instrument, with the reference it is SUPPOSED to track and one plain sentence a
# non-technical reader can finish. `peg` of None means the instrument is not a dollar claim and is
# therefore not judged against one.
#
# WHAT REMAINS DECLARED HERE, and why it is not a hardcoded price.
#
# Two things cannot be discovered from a token list and are therefore stated: what an instrument is
# BACKED BY, and what it is SUPPOSED to be worth. No API returns "PYUSD is backed by US Treasury
# repo under NYDFS supervision" or "sUSDe accrues yield so it must not be peg-checked". Those are
# facts about the real world, they are the entire basis on which the RWA guard judges anything, and
# writing them down is the opposite of faking data. What is NOT written down here is any address,
# any price, or any divergence: those all come from the chain.
#
# `peg` of None means the instrument is not a dollar claim and is not judged against one.
INSTRUMENT_FACTS = [
    ("PYUSD", 1.0, "PayPal's dollar. Backed by US government debt and cash."),
    ("USDG", 1.0, "Global Dollar. Backed by cash reserves."),
    ("USDC", 1.0, "Backed by cash and short-dated US Treasuries."),
    ("USDT", 1.0, "The largest dollar token. Reserve-backed, including Treasuries."),
    ("DAI", 1.0, "Backed by a basket of collateral held in contracts."),
    ("crvUSD", 1.0, "Backed by crypto collateral, redeemable against it."),
    ("USDe", 1.0, "A synthetic dollar. Held steady by hedging, not by reserves, so it can move."),
    # NOT judged against a dollar, deliberately. sUSDe accrues yield, so a price above 1.00 is the
    # instrument working correctly. Measuring it against a peg would report success as a breach.
    ("sUSDe", None, "USDe that earns yield. Worth more than a dollar on purpose, so it is not peg-checked."),
]


def discover(c):
    """Ask the chain which of these instruments it currently lists, and at what address.

    Returns (instruments, delisted). `instruments` is (symbol, address, peg, plain); `delisted` is
    every symbol this file knows a fact about that the chain no longer carries, which is reported
    rather than skipped, because an instrument disappearing from X Layer is itself news.
    """
    r = signed_get(ALL_TOKENS.format(chain=CHAIN), c)
    if not r or r.get("code") != "0":
        return None, None

    listed = {}
    for t in r.get("data", []):
        sym = (t.get("tokenSymbol") or "").strip()
        addr = t.get("tokenContractAddress")
        if sym and addr and sym not in listed:
            listed[sym] = addr

    instruments, delisted = [], []
    for symbol, peg, plain in INSTRUMENT_FACTS:
        addr = listed.get(symbol)
        if addr:
            instruments.append((symbol, addr, peg, plain))
        else:
            delisted.append(symbol)
    return instruments, delisted


def _usdt(c):
    """USDT's address, from the chain's listing. Was a literal; see tokens.py for why that is a bug.

    Matters more here than elsewhere: X Layer lists BOTH `USDT` and `USDT_Bridged`, so the wrong
    one would silently route every tradability check through a different asset's pools and report
    healthy instruments as unroutable.
    """
    import tokens

    return tokens.address("USDT", c)


def tradable(addr, c):
    """Can a single unit of this token actually be routed to USDT right now?

    WHY THIS EXISTS, and it is the most important function in the file.

    The price endpoint reported USDe at $26.57, which as a dollar token is a 255,677 bps breach.
    Shipping that verdict would have been shipping a lie: asking the aggregator to route one USDe
    to USDT returns

        "The value difference from this transaction's quote route is higher than 90%, which may
         lead to a risk of loss to user assets."

    The router will not touch it. So the instrument is not depegged, it is UNTRADEABLE on this
    chain, and its quoted price is not corroborated by anything you could execute against.

    Those two states demand different words on screen and a different verdict from the guard. A
    depeg is a market event. An untradeable token with an uncorroborated price is a data problem,
    and calling it a depeg would put a precise-looking number next to something nobody measured.

    Returns (ok, reason). `ok` False with a reason is a finding, never a failure to be swallowed.
    """
    usdt = _usdt(c)
    if addr.lower() == usdt.lower():
        return True, "quote asset"
    r = signed_get(
        f"/api/v6/dex/aggregator/quote?chainIndex={CHAIN}&amount=1000000000000000000"
        f"&fromTokenAddress={addr}&toTokenAddress={usdt}",
        c,
    )
    if not r:
        return False, "no response from the router"
    if r.get("code") == "0" and r.get("data"):
        return True, "routable"
    return False, str(r.get("msg") or "the router declined to quote this token")


def main():
    c = creds()
    if not c:
        print("No OKX credentials at ~/.asml-keys/okx.env. Writing nothing.")
        return 1

    INSTRUMENTS, delisted = discover(c)
    if INSTRUMENTS is None:
        print("Could not read the chain's token list. Writing nothing rather than using stale addresses.")
        return 1
    if not INSTRUMENTS:
        print("The chain lists none of these instruments. Writing nothing.")
        return 1
    print(f"discovered {len(INSTRUMENTS)} instruments from the chain's own token list")

    limit_bps, limit_verified = divergence_limit_bps()
    print(
        f"divergence band {limit_bps} bps, "
        + ("read from RwaRiskGuard on chain 196" if limit_verified
           else "RPC DID NOT ANSWER, using the fallback and marking it unverified")
    )
    if delisted:
        print(f"no longer listed on chain {CHAIN}: {', '.join(delisted)}")

    body = [{"chainIndex": CHAIN, "tokenContractAddress": a} for _, a, _, _ in INSTRUMENTS]
    r = signed_post("/api/v6/dex/market/price", body, c)
    if not r or r.get("code") != "0":
        print(f"Onchain OS price call failed: {r.get('msg') if r else 'no response'}")
        return 1

    by_addr = {d["tokenContractAddress"].lower(): d for d in r.get("data", [])}

    rows, breached, quoted = [], 0, 0
    for symbol, addr, peg, plain in INSTRUMENTS:
        d = by_addr.get(addr.lower())
        if not d or not d.get("price"):
            # ABSENT, NOT ZERO. A missing quote is reported as missing. Substituting 1.00 would
            # report a perfect peg for an instrument nobody could price, which is the single most
            # dangerous thing this file could say.
            rows.append({
                "symbol": symbol, "address": addr, "plain": plain,
                "price": None, "status": "no_quote",
            })
            continue

        quoted += 1
        price = float(d["price"])
        row = {
            "symbol": symbol,
            "address": addr,
            "plain": plain,
            "price": f"{price:.6f}",
            "quoted_at_ms": d.get("time", ""),
        }
        if peg is None:
            row["status"] = "not_peg_checked"
            row["reference"] = "none"
        else:
            div = (price - peg) / peg * 10_000
            row["reference"] = f"{peg:.2f}"
            row["divergence_bps"] = f"{div:.2f}"
            if abs(div) <= limit_bps:
                row["status"] = "within_band"
            else:
                # A BREACH IS NOT BELIEVED UNTIL A SECOND SOURCE AGREES. The price endpoint and
                # the router are independent; if the router will not quote the token at all, the
                # price is uncorroborated and the honest verdict is "cannot be priced", not a
                # depeg measured to two decimal places.
                ok, why = tradable(addr, c)
                time.sleep(0.35)
                if ok:
                    row["status"] = "breached"
                    row["corroborated_by"] = "the router quotes this token, so the price stands"
                    breached += 1
                else:
                    row["status"] = "untradeable"
                    row["router_says"] = why
                    # The divergence figure is REMOVED rather than shown with a caveat. Leaving a
                    # number on screen next to the words "cannot be priced" invites the reader to
                    # believe the number.
                    row.pop("divergence_bps", None)
        rows.append(row)

    out = {
        "source": "OKX Onchain OS DEX market price, signed",
        "endpoint": "POST /api/v6/dex/market/price",
        "chain_id": int(CHAIN),
        "chain_name": "X Layer mainnet",
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "divergence_limit_bps": str(limit_bps),
        "divergence_limit_verified_on_chain": limit_verified,
        "instruments": rows,
        "quoted": quoted,
        "breached": breached,
        # Every address above was read from the chain's own token list on this run, not typed into
        # this file. Recorded so the claim is checkable rather than asserted.
        "addresses_discovered_from": f"GET /api/v6/dex/aggregator/all-tokens?chainIndex={CHAIN}",
        "delisted": delisted,
        # Stated in the data rather than only in this docstring, so the UI can show the limitation
        # instead of the reader having to discover it.
        "absent_asset_classes": (
            "There is no tokenized gold, silver or stock index you can safely trade here. Tokens "
            "with names like stocks do appear on this chain, but none is listed by the exchange "
            "aggregator and nothing verifies they are backed by the shares they are named after. "
            "They are not shown as real-world assets, because a name is not a backing."
        ),
        # THE LONGER FINDING, kept next to the claim it supports.
        #
        # Asked where gold, silver and Nasdaq were, the first answer was that X Layer's 22
        # aggregator-listed tokens contain no such instrument. That remains true. What the smart
        # money feed then surfaced is a token called "NVDA RTX STOCKS" (RTX,
        # 0x18a4f9d450f46f9dea99da758b4c29ad620aae93, 807 holders). It scans LOW risk and is not a
        # honeypot, so it is not obviously malicious, and it is ALSO not in the aggregator's
        # routable list and carries no evidence of holding NVDA shares.
        #
        # Presenting it as equity exposure would be the exact failure this product argues against:
        # putting a real-looking number in front of someone and letting the name do the work that
        # backing is supposed to do. It is excluded, and the reason is on the screen.
        "naming_note": (
            "Checked and excluded: RTX / 'NVDA RTX STOCKS' on chain 196. Scans as low risk, but is "
            "not aggregator-listed and has no verifiable share backing."
        ),
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)

    os.makedirs(os.path.dirname(EVIDENCE), exist_ok=True)
    with open(EVIDENCE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("Real-world assets on X Layer mainnet, priced by OKX Onchain OS\n")
        fh.write(f"Run {out['fetched_at_utc']}\n\n")
        fh.write(json.dumps(out, indent=2))
        fh.write("\n")

    for row in rows:
        if row["price"] is None:
            print(f"  {row['symbol']:<8} no quote returned")
        elif row.get("divergence_bps") is not None:
            print(
                f"  {row['symbol']:<8} ${row['price']}  "
                f"{float(row['divergence_bps']):+.2f} bps from $1.00  {row['status']}"
            )
        elif row["status"] == "untradeable":
            print(f"  {row['symbol']:<8} price uncorroborated, router declined: {row['router_says'][:60]}")
        else:
            print(f"  {row['symbol']:<8} ${row['price']}  not peg-checked (yield-bearing)")

    print(f"\n{quoted} of {len(INSTRUMENTS)} priced, {breached} outside the {limit_bps} bps band")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
