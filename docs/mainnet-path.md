# Mainnet path

This submission is **testnet only**, deliberately. This document is the forward commitment:
what changes, what the risk differences are, and the volume roadmap.

Status of everything below: `INFERRED`. It is a plan, not a demonstration. Nothing here is
claimed as done.

---

## Why testnet only for the submission

The hackathon rules require deployment on X Layer testnet during the event and a mainnet
launch subsequently. "Subsequently" reads as a forward commitment, so no mainnet deployment
was made and no real funds were spent. Recorded in
[decisions/ADR-003-testnet-only.md](decisions/ADR-003-testnet-only.md).

Total cost of the entire testnet build: under 0.001 OKB.

---

## What actually has to change

The honest answer is that most of the code does not change, and the parts that do are the
parts that should be rewritten anyway rather than promoted.

| component | change needed | effort |
|---|---|---|
| `core-types`, `risk-engine` | None. Pure, no I/O, no clock. Limits get retuned, not rewritten. | hours |
| `chain-client` | Point at mainnet RPC and chain 196. Verify independently of testnet values. | hours |
| `market-intel`, `decision-engine`, `journal`, `learning` | None structurally. | none |
| Signing | **Replace the `cast` subprocess.** Acceptable on testnet, not for mainnet: a subprocess per submission is latency and an unnecessary process boundary around a key. Move to a proper in-process signer. | days |
| `coordination-api` | **Fix the burst stall first.** Thread per connection with `State` behind a `Mutex`, or replace the hand-rolled loop with `tiny_http` 0.12. Non-negotiable before exposing it publicly. | days |
| `OrderBookVenue` | **Replace, do not deploy.** This is the piece to drop in favour of a real venue. | n/a |
| `RwaVault` | **Replace with a real instrument.** It is a stand-in. | n/a |
| `RiskGuard`, `RwaRiskGuard`, `BatchExecutor` | Redeploy as-is, then re-run the full mutation and Halmos suites against the deployed bytecode. | days |

### The venue adapter is two calls wide

The agent depends on the venue through exactly two shapes: an order book read
(`orderCount()` plus `orders(uint256)`) and a take (`take(uint256,uint256)`). The RWA layer
depends on `riskView()` on the instrument and `divergenceBps()` on the guard.

That is the whole coupling surface. Any real venue or RWA protocol exposing an oracle mark
with a timestamp, a pause flag, and a redemption schedule can be adapted behind those calls
without touching the risk engine, the decision engine, or the learning layer.

### If and when Exchange OS opens

Exchange OS has no testnet developer surface today
([verified/exchangeos-availability.md](verified/exchangeos-availability.md)), and press
indicates external-builder venue deployment via XIP governance in Q3 2026.

The first task at that point is not to write an integration. It is the reverse-engineering
step this project already ran against the rest of the chain: pull the deployed contracts and
ABIs, decode 50 or more real transactions from a live venue, write down the actual calldata
shapes and event topics, and diff that against the documentation. The chain wins every
disagreement. `docs/verified/` exists to hold that output, and
`docs/verified/chain-1952-reality.md` is the template: it corrected chain ID 195 to 1952 and
settled the OP Stack question from bytecode rather than prose.

Only after that does the adapter get written, and it goes behind the same two calls.

---

## Sequenced plan

Dates are commitments, not estimates padded for safety.

### Week 1, 22 to 28 Aug 2026: harden

- Fix the coordination burst stall. This blocks any public endpoint.
- Replace the `cast` signing shim with an in-process signer, with the keystore never leaving
  the process.
- Re-tune limits for real capital. The current values are testnet-conservative in the wrong
  way: small absolute caps rather than sensible ratios.
- Run the 60-minute unattended soak that was never done, then a 24-hour one.
- Clean the 9 clippy warnings, get CI green on the public repo.

### Week 2, 29 Aug to 4 Sept 2026: mainnet deploy, minimum surface

- Deploy `RiskGuard`, `RwaRiskGuard`, `BatchExecutor` to X Layer mainnet, chain 196. Verify
  source on the explorer.
- Re-run all four mutation gates and both Halmos suites against the deployed bytecode.
- Run the agent in **human-approval mode only**, with the approval threshold set to zero so
  every action requires a human. Tiny size.
- Publish the first mainnet transaction with an explorer link.

### Month 1 to 3, Sept to Nov 2026: real venue, real flow

- Integrate a real venue. Priority order: Exchange OS if XIP deployment has opened,
  otherwise whatever DEX has genuine liquidity on X Layer mainnet.
- Integrate a real RWA instrument, replacing `RwaVault`. The four reads are already the
  interface.
- Raise the human-approval threshold only after the learning layer has a sample size worth
  the name. Current single-digit samples justify nothing.
- Open the coordination API to external agents with real keys and per-caller quotas.

### Month 3 to 12: the parts this prototype only gestures at

- Multi-venue risk engine with cross-venue netting.
- Learning with retrieval of similar past states (plan 7.2.3, unbuilt).
- Realized PnL accounting, which the entire project currently lacks and without which no
  performance claim is possible.
- Liquidity-hub effects: other agents depending on the brain for quotes and capacity.

---

## Launch Grant volume mechanics

Recorded here because the numbers are specific and easy to get wrong.

- **50,000 USDT unlocked per full 10,000,000 USDT** of cumulative trading volume.
- Volume must be generated **via the OKX DEX interface**.
- **API-executed volume is excluded.** This is the constraint that matters most for an
  autonomous agent, because an agent's natural execution path is exactly the excluded one.
- Cutoff: **31 Aug 2026, 23:59 UTC+8**. Snapshot 1 Sept, anti-fraud reviewed.
- Up to 200,000 USDT total.

**Honest assessment:** the API exclusion means an autonomous agent cannot itself generate
qualifying volume by trading through an API. Reaching the Launch Grant therefore requires
routing through the OKX DEX interface, or driving human volume to it, neither of which this
prototype does today. Given the 31 Aug cutoff is ten days after submission, the realistic
position is that the Launch Grant is **not** reachable for this project in that window, and
claiming otherwise would be arithmetic nobody should believe.

The Hackathon Grant and the AI-RWA Liquidity Grant are the reachable targets.

---

## What would make this credible rather than aspirational

If you are assessing whether the plan above is real, these are the checkable signals, in
order of how much they would tell you:

1. A mainnet transaction from `RiskGuard` with the mutation gates re-run against deployed
   bytecode. That is a weekend of work and it is either done or it is not.
2. The coordination burst stall fixed, with the rate limiter finally observed tripping.
3. A 24-hour unattended run with the journal intact and no memory growth.
4. Realized PnL accounting landing, which converts every performance statement in this
   project from unmeasurable to measurable.

Items 1 through 3 are scheduled above within two weeks of submission. Item 4 is the honest
gate on any claim that this system makes money, and it is deliberately not promised early.
