# The seeded order book is no longer the source of truth

## What was wrong

The agent perceived an order book this project deployed and seeded. Every number downstream was
internally consistent and externally meaningless: a spread we chose, a depth we posted, a crossed
book we created. "2236 refusals" counted real refusals against a market we invented.

`scripts/okx_depth.py` replaces it with measured liquidity.

## Method

A real order book prices size. So does the OKX Onchain OS aggregator: a quote for 1 WOKB and a
quote for 1000 WOKB do not return the same unit price, because the second walks further into real
pools. One signed call to `/api/v6/dex/aggregator/quote` per rung; the differences ARE the depth
curve. Nothing is modelled or interpolated.

## Measured, WOKB/USDT on X Layer mainnet (chain 196)

```
  size      unit price        router impact   venues crossed
     1 WOKB  97.393939 USDT     0.02%          Uniswap V3
    10 WOKB  97.364155 USDT    -0.03%          Uniswap V3, Caliber propAMM
   100 WOKB  97.312967 USDT    -0.09%          Uniswap V3, Caliber propAMM
  1000 WOKB  94.534822 USDT    -2.93%          Uniswap V3, PotatoSwap, Uniswap V4,
                                               Caliber propAMM, Revoswap V2, PotatoSwap V3,
                                               OkieSwap V3, OkieStableSwap
```

**Eight real venues.** Not one contract this project deployed.

## The curve is corroborated, not asserted

Slippage is derived independently from the ladder and compared against the router's own
`priceImpactPercent`, which is a separate field computed by OKX rather than by this script:

```
derived from ladder at 1000 WOKB:  (97.393939 - 94.534822) / 97.393939 = 293.4 bps = 2.93%
router's own priceImpactPercent:                                        -2.93%
```

Two independent measurements of the same quantity agreeing to two decimal places. If the ladder
arithmetic were wrong, these would diverge.

## The finding this produces

**X Layer's WOKB/USDT liquidity is thin above roughly 100 WOKB.** Inside the risk engine's 100 bps
tolerance the largest safe size is 100 WOKB; 1000 WOKB costs 293 bps and fans out across eight
pools. That is a real property of a real chain, and it is the kind of limit the risk gate exists
to enforce. It could not have been discovered against a book we seeded ourselves.

## A wrong address, caught by reading a response

The first run quoted WOKB against `0x1e4a5963...`, and the aggregator answered by routing
WOKB -> `0x779ded0c...` USDT -> that address: a two-hop path whose second hop added slippage
having nothing to do with WOKB's depth, which is why the first run reported 71.43 at 1000 WOKB
instead of 94.53. Quoting against the USDT the router settles in measures the pair rather than the
detour.

The venue list was also empty on the first run: the parser assumed
`dexRouterList[].subRouterList[].dexProtocol[]`. The real shape is
`dexRouterList[].dexProtocol` as a single object. Reading one actual response fixed both. Neither
was guessable, and both were silent failures rather than errors.

## Data points now kept per rung

`unit_price`, `venues`, `router_price_impact_pct`, `estimated_gas`, `is_honeypot`, `tax_rate`.
The first version kept only the price and discarded the rest, which was the same "not using the
data you have" failure in miniature.

## Wired into the agent, not just displayed

`crates/market-intel/src/external.rs` gains `RealDepth`, `load_depth`, `max_safe_size`,
`venues` and `with_real_depth`. `crates/runtime/src/main.rs` applies it in the perceive step
before volatility, and stamps every decision with `depth_source`, `depth_pair`, `depth_venues`
and `max_safe_size_base`, so the journal states per decision whether the size limit it reasoned
about came from measured pools or from our own book.

```
cargo test -p market-intel     29 passed, 0 failed
cargo clippy -p runtime -p market-intel --all-targets    no warnings
```

Four of those tests exist specifically to stop this going wrong quietly:

- `the_largest_safe_size_is_read_off_measured_slippage` pins 100 WOKB against the real ladder.
- `a_pair_too_thin_to_trade_says_so_rather_than_allowing_the_smallest_size` proves a market where
  every rung breaches tolerance returns `None`, not "the smallest size is fine".
- `the_spread_comes_from_the_largest_tolerated_size_not_the_smallest` proves the cost figure is
  the cost of the size the agent may actually trade, not the flattering top-of-ladder zero.
- `a_one_rung_file_is_rejected_because_it_would_imply_zero_slippage` proves a degenerate file is
  refused rather than read as a frictionless market.

## On screen, in the user's language

The Markets surface renders the ladder as "What size the market can take", read off the live page:

```
SIZE          EXTRA COST   ALLOWED
1 WOKB        none         Yes
10 WOKB       3 bps        Yes
100 WOKB      8 bps        Yes
1000 WOKB     294 bps      Too big

The agent will not trade more than 100 WOKB at once
8 venues on X Layer mainnet. None of them belong to this project.
```

## Reproduce

```
python3 scripts/okx_depth.py
```

Writes `ui-v2/public/data/depth.json` and `evidence/phase19/real-depth.txt`. Requires OKX
credentials at `~/.asml-keys/okx.env`, outside the repo.
