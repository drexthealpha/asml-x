# ASML-X

An AI agent that trades real tokens on X Layer, and cannot exceed the limit you set.

Live on **X Layer mainnet, chain 196**.

---

## What it does

You deposit, you set the most it may ever risk, and it trades under that cap. You can take your
money out at any time, including while the agent is paused.

The interesting part is what it *refuses*. Across the decisions in the current journal the agent
considered **720 possible trades and made 16**, turning down 688 because they broke a rule. That
ratio is the product: an agent worth trusting with money is one that mostly declines.

| Reason it declined | Count |
|---|---|
| A safer option scored better | 376 |
| Not enough money left to cover it safely | 249 |
| Bigger than your limit allows | 63 |

---

## Three guarantees, and how each is enforced

These are not policies. Each is structural, and each is proved.

| Guarantee | Enforced by | Proof |
|---|---|---|
| Your limit can only be lowered | `RiskGuard` has no widening code path | Halmos symbolic execution |
| Learning cannot widen a limit | `Learner` has no type mentioning `Limits` | Compile-time |
| The agent cannot skip the check | `RiskApproved<T>` is sealed in `risk-engine` | Code that tries fails to **compile** |
| Pause never blocks withdrawal | Withdrawal is not gated on agent state | Halmos |

`RouterExecutor` additionally measures its own balance before and after every swap and reverts
unless it received at least the aggregator's stated minimum — verified rather than trusted. That
check is mutation-tested: deleting it turns exactly the two theft tests red.

---

## Real data, end to end

Every number on every screen comes from a signed OKX Onchain OS call or a chain read. Nothing is
seeded, defaulted, or illustrative.

- **Prices** — token price *and* an independent aggregated index price, so the RWA divergence check
  compares two genuinely different sources rather than a price to itself
- **Depth** — a measured ladder across 8 real venues; the agent's size limit comes from what the
  pools will actually pay, not from a book we posted
- **Security** — honeypot, tax, mintability and holder concentration on every token, from OKX's own
  scanner
- **Yield** — live Aave V3 on X Layer, real APY and TVL
- **Signals** — smart-money purchases and social sentiment, which move the agent's *confidence* and
  never its limits

Token addresses are discovered from the chain's own listing on every run. There is not one
hardcoded address, price, or balance in the frontend.

---

## Run it

```bash
# 1. credentials, outside the repo
mkdir -p ~/.asml-keys
cat > ~/.asml-keys/okx.env <<'EOF'
OKX_API_KEY=...
OKX_SECRET=...
OKX_PASSPHRASE=...
EOF
chmod 600 ~/.asml-keys/okx.env

# 2. the OKX CLI
bash scripts/oos.sh --help

# 3. feeds + UI
bash scripts/221-feed-server.sh
```

The browser never holds the API secret: signing happens in `scripts/feed_server.py` and the page
receives results with the age of each attached.

## Verify it

```bash
cargo test --workspace                    # 21 suites
bash scripts/213-router-tests.sh          # RouterExecutor, 10 tests
bash scripts/214-router-mutation.sh       # proves the balance check is load-bearing
bash scripts/224-x402-gate.sh             # agent-to-agent payment gate
```

---

## Architecture

Diagrams: [docs/architecture.md](docs/architecture.md)

## Known limitations

Stated here rather than discovered later.

- **WebSocket streaming is not enabled.** The socket authenticates with our key, but every channel
  returns *"Only users who are in the whitelist are allowed to subscribe."* That is an OKX account
  permission. The client is correct and needs no change when it is granted; until then the product
  polls, and labels the age of every figure. See `evidence/phase20/websocket.md`.
- **Agentic Wallet features are not wired.** TEE-held keys, limit orders and Gas Station all
  require a browser social login that cannot be automated. The API key authenticates every read
  surface but does not create a wallet.
- **ERC-8004 identity is not registered**, for the same reason: it needs an Agentic Wallet address.
- **There is no tokenized gold, silver or equity index you can safely trade here.** Tokens named
  after stocks exist on this chain; none is listed by the aggregator and nothing verifies backing,
  so none is presented as a real-world asset. A name is not a backing.

## Licence

MIT.
