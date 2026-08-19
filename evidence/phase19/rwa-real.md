# The RWA surface now holds real-world assets

## What it held before

tBASE and tQUOTE: two ERC20s this project deployed, at a price this project set, compared against
each other. As an answer to "show me the real-world assets" that was indefensible.

## The absence, checked rather than assumed

There is **no tokenized gold, silver, or equity index on X Layer.** This is the complete token list
Onchain OS returns for chain 196, read symbol by symbol:

```
USDG USDT USDC ETH SOL OKB crvUSD DAI DMCX FB PYUSD QUICK sUSDe STONE
USDT_Bridged USDC_Bridged USDe WBTC WOKB xBTC xBETH xOKSOL
```

No XAUT, no PAXG, no index product. Attaching an off-chain gold price would put a number on screen
that the agent cannot trade, the vault cannot hold, and the risk gate cannot enforce anything
about. The product says what is missing instead of inventing it.

## What is there is the strongest kind of RWA for a risk product

Dollar tokens backed by US Treasuries and cash. Their reference is exactly $1.00, divergence is
measurable to the basis point, and the deployed `RwaRiskGuard` already enforces a 300 bps band.

Live, read off the running page:

```
USDG   $0.999911    0.9 bps from $1.00   holding its value
USDC   $0.999852    1.5 bps from $1.00   holding its value
USDT   $0.998609   13.9 bps from $1.00   holding its value
DAI    $1.000077    0.8 bps from $1.00   holding its value
USDe   no usable price                   refused
```

Every price is a signed `POST /api/v6/dex/market/price` to OKX Onchain OS for chain 196.

## A false depeg, caught by a second source

The price endpoint reported **USDe at $26.567701**, which as a dollar token is a 255,677 bps
breach. Shipping that verdict would have been shipping a lie.

Asking the aggregator to route one USDe to USDT returns:

> The value difference from this transaction's quote route is higher than 90%, which may lead to a
> risk of loss to user assets.

**The router will not touch it.** So the instrument is not depegged, it is untradeable on this
chain, and its quoted price is not corroborated by anything executable. Those are different facts
and get different words.

`tradable()` in `scripts/okx_rwa.py` now runs before any breach is reported. When the router
declines, the status becomes `untradeable`, and the divergence figure is **removed from the
payload entirely** rather than shown with a caveat, because a number beside "cannot be priced"
gets believed anyway.

The same mistake then reappeared in the UI and was caught on the live page: the row printed
`$26.567701` next to "Cannot be priced". Verified fixed:

```
usdeShowsPrice: false
row reads:      "no usable price" / "Cannot be priced, so it is refused"
```

## Three tokens listed but not priced

PYUSD, crvUSD and sUSDe are on the chain-196 token list but Onchain OS returned no price for them.
They are shown in a "listed but not priced" panel as missing, never filled in with a dollar.

## The old comparator is not deleted

It moved to the `rwa-evidence` deep link. Comparing two markets we deployed is a claim about the
ENGINE (the RWA layer reads the instrument rather than braking globally), which is worth keeping
as evidence. It is not a real-world asset a reader can hold, so it no longer leads the surface.

## Reproduce

```
python3 scripts/okx_rwa.py
```

Writes `ui-v2/public/data/rwa.json` and `evidence/phase19/rwa-feed.txt`.
