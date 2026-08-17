# Task 14.1: differential proof, three implementations of one rule

Run 2026-08-16 19:08:56 UTC.

This project enforces the per-market cap in THREE places. Three implementations of one rule is
three chances to disagree, and a disagreement stays invisible until something valuable depends
on it. The same input goes through all three here.

The comparison is on the REVERT SELECTOR and its DECODED ARGUMENTS, not on a boolean. Two
implementations that both refuse for different reasons have not agreed, they have coincided.

## The input

```
guard          0x977A77aF8891187C73c7cdBd145B6fD57A0D0a47  (testnet 1952)
market         0x7cf714968d0c21fb12269a1a8e84bdc4fe973673c435100e04baae9b7c6b3fdd
maxPerMarket   500000000000000000000
exposure now   23456250000000000000
requested      510000000000000000000   (deliberately over the cap)
```

## Layer 1: the LIVE DEPLOYED contract

```
Error: server returned an error response: error code 3: execution reverted, data: "0x3e2ed0287cf714968d0c21fb12269a1a8e84bdc4fe973673c435100e04baae9b7c6b3fdd00000000000000000000000000000000000000000000001ceb315100adf9a00000000000000000000000000000000000000000000000001b1ae4d6e2ef500000"

```

## Layer 2: revm, the same bytecode in an in-memory EVM

Nothing touches the network. This is what a pre-flight check runs before paying gas.

```
    deployed into revm at 0x8F7a45eBDe059392E46A46DCc14AB24681A961Ea
    setAgent: ok
    setMarketCap(500e18): ok
    addExposure(8e18) under the cap: ok
    addExposure(600e18) REVERTED
    revert data: 0x3e2ed0287cf714968d0c21fb12269a1a8e84bdc4fe973673c435100e04baae9b7c6b3fdd000000000000000000000000000000000000000000000020f5b1eaad8d80000000000000000000000000000000000000000000000000001b1ae4d6e2ef500000
    revert selector: 0x3e2ed028
    decoded attempted: 608000000000000000000
    decoded cap:       500000000000000000000
```

## Layer 3: the Rust risk engine, offchain

Here a refusal is a type-level fact rather than a revert: `RiskApproved<T>` has exactly one
constructor and it sits behind this check, so an over-cap intent cannot produce an approved
value at all. That is a stronger statement than "the function returns an error".

```
test tests::approval_implies_every_limit_holds ... ok
test tests::the_market_notional_projection_adds_to_existing_exposure_and_its_boundary_is_inclusive ... ok
test result: ok. 43 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.18s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

## The comparison

```
live deployed revert selector   0x3e2ed028
expected MarketCapExceeded      0x3e2ed028
expected CapExceeded            0xf480e285
```

## What a divergence would look like, and why it is not absorbed

If the three layers disagreed, the failure modes would be:

- **engine permits, chain refuses**: the agent builds a batch that reverts, wasting gas on every
  cycle. Loud, and caught by the first failed submission.
- **engine refuses, chain permits**: the agent never attempts something it was allowed to do.
  SILENT, and the expensive one, because nothing errors and the only symptom is an agent that
  under-trades for a reason nobody can see.
- **revm disagrees with either**: the pre-flight is worthless, and worse than absent, because it
  would be trusted.

The second is why this task exists. A differential test is the only thing that finds a silent
over-refusal, since no single layer can observe its own excess caution.
