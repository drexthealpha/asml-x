# Submission post

For the project X account. Tags @XLayerOfficial.

---

## Main post

> Most AI trading agents ask you to trust them.
>
> ASML-X is built so you don't have to.
>
> It trades real tokens on @XLayerOfficial — and it **cannot** exceed the limit you set. Not
> "shouldn't". Cannot.
>
> Live on chain 196 🧵

---

## Thread

**2/**
> The interesting number isn't what it traded. It's what it refused.
>
> 720 trades considered. 16 made. 688 stopped.
>
> An agent worth trusting with money is one that mostly says no.

**3/**
> Three guarantees, each structural rather than promised:
>
> • Your limit can only be lowered, never raised
> • The learning layer physically cannot touch the limits — no type connects them
> • Code that tries to trade without approval doesn't compile
>
> Proved with Halmos, not asserted in a README.

**4/**
> Every trade routes through @OKX Onchain OS across real X Layer liquidity — Uniswap V3/V4,
> PotatoSwap, OkieSwap, Revoswap, Caliber.
>
> The executor measures its own balance before and after each swap and reverts if it's short.
> It verifies. It doesn't trust.

**5/**
> Every asset is priced twice: once from the pools, once from an independent index.
>
> When they disagree beyond the band, trading stops.
>
> A safety check comparing a price to itself can never fail. This one can.

**6/**
> It also tells you when NOT to trade.
>
> DAI on X Layer: $713 of liquidity, 93% held by the top 100 wallets.
>
> Looks like the DAI you know. Isn't. You'd be the exit liquidity.

**7/**
> Other agents can pay for a quote over x402 — HTTP 402, sign, retry. No API key, no account.
>
> Paying buys the quote. It does not buy a bigger one: the risk gate runs identically either way.

**8/**
> Open source, MIT. Every claim reproduces from a clean clone.
>
> Code: github.com/drexthealpha/asml-x
> Live: [VERCEL URL]
>
> Built for the BuildX AI Season Hackathon on @XLayerOfficial

---

## Short version

> An AI agent that trades real tokens on @XLayerOfficial and cannot exceed the limit you set —
> enforced by the type system, proved with symbolic execution.
>
> 688 of 720 trades refused. That's the product working.
>
> [URL]

---

## Notes before posting

- Replace `[VERCEL URL]` with the deployed link
- The 688/720 figures come from `ui-v2/public/data/activity.json`; refresh them if the agent has
  run since
- The DAI figures are live and will move — re-check before posting
