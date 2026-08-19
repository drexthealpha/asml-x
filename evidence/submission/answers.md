# Submission answers

Written against the seven judging criteria. Every claim here has a command that reproduces it.

---

## 1. Application of AI

The agent perceives a real market, forms a thesis, generates candidates from measured depth,
scores each on four terms, and is gated by a risk engine it cannot bypass.

- **Live thesis from real signals.** Spread, realized volatility, imbalance and depth are measured
  from an OKX depth ladder across 8 real venues, not from an order book we posted. Before this,
  the agent read a seeded book that was crossed (bid 1.90 above ask 1.70), correctly refused
  everything, and held every cycle at 0% confidence. It now reads 5000 bps confidence off a real
  spread of 8 bps against 5 bps volatility.
- **Candidates from live depth, not a fixed menu.** `generate_within` sizes every buy against the
  real balance and the measured slippage curve. Four tests pin that the bound only ever shrinks a
  candidate, never blocks a sell, and never emits a zero-size order.
- **Four-term scoring** — expected edge, variance penalty, capital cost, execution risk — kept
  separately so the journal can explain any decision.
- **Learning from settled trades only**, and structurally unable to widen a limit: `Learner` has no
  type that mentions `Limits`.
- **Coordination API** other agents call, now with x402 payment.
- **Gated, provably.** `RiskApproved<T>` is sealed. Code that trades without it does not compile.

Reproduce: `cargo test --workspace`

---

## 2. Innovation

The claim is not "an AI that trades". It is **an autonomous agent with guarantees a user can
check**, and the guarantees are structural rather than promised.

| Property | Enforcement |
|---|---|
| Limits only tighten | No widening path exists in `RiskGuard` |
| Learning cannot widen limits | No type connects `Learner` to `Limits` |
| Agent cannot skip the gate | `RiskApproved<T>` sealed; bypass fails to compile |
| Pause never blocks withdrawal | Withdrawal not gated on agent state |

Proved with Halmos symbolic execution, and a second independent prover. The risk engine uses no
floating point and reads no clock: time is an argument, which is what makes it verifiable.

`RouterExecutor` measures its own balance delta around every swap and reverts on shortfall — it
verifies rather than trusts the aggregator. Mutation-tested: deleting that check turns exactly the
two theft tests red.

Reproduce: `bash scripts/214-router-mutation.sh`

---

## 3. Product completeness

Connect → deposit with a cap → agent trades under it → withdraw any time, including while paused.
All on mainnet.

- Wallet: browser extension **and** WalletConnect (QR), one code path for both
- Real deposit and withdrawal of a real token, limit set in the same transaction so funds are never
  uncapped
- Five surfaces, every row opens a detail panel, 25 tokens covered
- Empty, loading and failure states designed; a failed fetch never renders as a zero
- Mobile at 375px

---

## 4. User value

The first screen answers it: put money in, set a cap the agent cannot exceed, take it out whenever.

**Refusals are the headline, not an embarrassment.** The agent surface leads with *"688 trades
stopped before they happened"* and explains why in plain English. Every engine reason is
translated — `InsufficientFreeMargin { would_leave: 22, minimum: 5000000 }` becomes *"Not enough
money left to cover it safely"* — with a catch-all so no raw enum can reach a user.

The detail panel earns its place: DAI on X Layer shows **$713 of liquidity with 93.1% held by the
top 100 wallets**. Without that, someone sees "DAI, $1.0001, low risk" and assumes it is the DAI
they know. It stops a real loss.

---

## 5. Integration with X Layer

Everything runs on chain 196. Contracts are linked to the public explorer from the app footer.

- Real swap executed: `0xd705bb95b2284b0253a18fb91418bb110ba27a6e1d3c28a9d6ddf1446b3885b5`
  (0.002 WOKB → 0.198978 USDT through Uniswap V3)
- Execution through the **OKX Onchain OS aggregator**, across Uniswap V3/V4, PotatoSwap,
  OkieSwap, Revoswap and Caliber
- Real prices for WBTC, xBTC, ETH and the dollar tokens, each with an independent index price
- Live Aave V3 on X Layer, $50.4M TVL
- No seeded order book anywhere in the decision path

---

## 6. Growth potential

- Coordination API with **x402**, so any Onchain OS agent can pay for a quote with no bespoke
  integration
- Venues and oracles are discovered, not configured: a new token on X Layer appears with no code
  change
- Limits extend without touching the core
- A new developer can run the whole stack from the README

---

## 7. Contribution to the ecosystem

- Public repo, MIT licensed
- Every claim reproduces from a clean clone
- Limitations stated in the README rather than discovered by a judge
- Real trading volume path through the OKX DEX interface

---

## Honest limitations

- **WebSocket streaming is not enabled.** Authenticates with our key; every channel returns
  *"Only users who are in the whitelist are allowed to subscribe."* An OKX account permission. The
  client is correct and unchanged when granted.
- **Agentic Wallet features are not wired** — TEE keys, limit orders, Gas Station. All need a
  browser social login that cannot be automated.
- **ERC-8004 identity is not registered**, for the same reason.
- **No tokenized gold, silver or equity index is tradable here.** Tokens named after stocks exist;
  none is aggregator-listed and nothing verifies backing, so none is shown as a real-world asset.
