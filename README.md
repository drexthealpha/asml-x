# ASML-X

An autonomous market brain running live on X Layer testnet, chain 1952.

It reads a real order book over JSON-RPC, forms a thesis from measured signals, scores a
generated candidate set, puts every candidate through a risk gate the agent cannot bypass,
submits multi-leg transactions atomically, and learns from realized outcomes. It has a
second layer of refusals that only make sense for RWA-linked instruments, and a
coordination API that another agent can call over HTTP.

Submission for the BuildX AI Season hackathon (X Layer). **Testnet only**, with a
documented mainnet path in [docs/mainnet-path.md](docs/mainnet-path.md).

Start here if you are judging: **[JUDGE-GUIDE.md](JUDGE-GUIDE.md)**, a five-minute path.

## Evidence labels

Every claim in this repository is tagged. `DEMONSTRATED` means shown true with a link to
the artifact. `INFERRED` means assumed from structure and not proven. Untagged claims are
treated as defects.

## What is real, and what is not

Read this before anything else, because two things in the original plan turned out not to
exist and the project says so rather than working around them quietly.

- **Exchange OS has no developer surface on X Layer testnet.** The official 23-page
  Exchange OS whitepaper contains zero contract addresses and zero occurrences of the word
  "testnet", and the X Layer developer documentation navigation contains zero references to
  Exchange OS, TradeZone, venues, or order books. Establishing that took four independent
  primary probes: [docs/verified/exchangeos-availability.md](docs/verified/exchangeos-availability.md).
  Exchange OS is therefore a labelled `INFERRED` migration target in this project, never a
  claimed integration. The live demo makes no Exchange OS claim at all.
- **The venue and the RWA instrument are ours.** Chain 1952 carries roughly 110 user
  transactions across 7 distinct contracts per 300 blocks, and no Uniswap factory or router
  exists at any canonical address, so there was nothing liquid to integrate against:
  [docs/verified/chain-1952-reality.md](docs/verified/chain-1952-reality.md). We deployed
  our own order book and our own RWA stand-in, both labelled `SELF-DEPLOYED STAND-IN`
  wherever they appear.

What that preserves: every transaction is real, onchain, and verifiable on a public
explorer. What it costs is stated plainly in [docs/limitations.md](docs/limitations.md).

## Architecture

```
                    chain 1952 (X Layer testnet, OP Stack Bedrock)
   ┌──────────────────────────────────────────────────────────────────────┐
   │  OrderBookVenue      RiskGuard ◄── BatchExecutor      RwaVault       │
   │  escrow, fills       caps,         atomic multi-leg   oracle, pause, │
   │                      kill switch   all-or-nothing     window, yield  │
   │                          ▲                                ▲          │
   │                    RwaRiskGuard ───────────────────────────┘          │
   │                    4 extra refusals, extends RiskGuard               │
   └──────────────────────────────────────────────────────────────────────┘
              ▲ eth_call / eth_sendRawTransaction (via cast)
              │
   ┌──────────┴───────────────────────────────────────────────────────────┐
   │  runtime (bin: asml)                                                 │
   │                                                                      │
   │  chain-client ──► market-intel ──► decision-engine ──► risk-engine   │
   │  JSON-RPC,        signals with     candidates,         limits, kill,  │
   │  static ABI       confidence and   4-term scoring      RWA refusals   │
   │                   staleness              │                  │        │
   │                                          ▼                  ▼        │
   │                                     journal ◄──── RiskApproved<T>    │
   │                                     JSONL audit    sealed token      │
   │                                          │                           │
   │                                     learning                         │
   │                                     outcomes, params, persistence    │
   └──────────────────────────────────────────────────────────────────────┘
              ▲                                    │
              │ HTTP                               ▼
   ┌──────────┴───────────┐              ┌────────────────────┐
   │ coordination-api     │              │ ui/index.html      │
   │ (bin: asml-coord)    │              │ reads journal +    │
   │ quote, accept,       │              │ learned state +    │
   │ thesis, capacity     │              │ deployments        │
   └──────────┬───────────┘              └────────────────────┘
              │
   ┌──────────▼─────────────────────┐
   │ agents/external_agent.py        │
   │ separate process and language   │
   └─────────────────────────────────┘
```

## The three design decisions that matter

**1. The agent cannot reach the chain except through the risk gate, and that is enforced by
the type system.** The signing path requires a `RiskApproved<OrderIntent>`, a token whose
only constructor lives inside the risk engine. Writing code that submits an unapproved
order does not fail a test, it fails to compile:
[evidence/bypass-compile-error.txt](evidence/bypass-compile-error.txt) `DEMONSTRATED`.

**2. The risk engine is pure: no floats, no clock reads.** `float_arithmetic` is denied at
the workspace lint level and time is passed in as an argument. Both properties exist so the
limits are formally verifiable, and retrofitting either later would have meant a rewrite.
See [ADR-005](docs/decisions/ADR-005-no-floats-no-clocks.md).

**3. Learning structurally cannot widen a risk limit.** The `Learner` type has no field,
argument, or return type anywhere in its API that mentions `Limits`. It produces scoring
parameters and nothing else, so the guarantee is a fact about which types exist rather than
a policy someone must remember.

## Verification

| gate | result |
|---|---|
| Rust tests | 19 suites, all green `DEMONSTRATED` |
| Solidity tests | 50 Foundry tests including 4 stateful invariant campaigns `DEMONSTRATED` |
| Formal verification | 7 + 7 Halmos theorems, each proven for all inputs in range `DEMONSTRATED` [evidence/formal/](evidence/formal/) |
| Proof mutation | an injected 1-wei cap violation and a removed pause refusal were both caught `DEMONSTRATED` |
| Mutation: risk engine | 14/14 RED [evidence/mutation-risk-engine.md](evidence/mutation-risk-engine.md) |
| Mutation: contracts | 15/15 RED [evidence/mutation-contracts.md](evidence/mutation-contracts.md) |
| Mutation: RWA layer | 18/18 RED [evidence/mutation-rwa.md](evidence/mutation-rwa.md) |
| Mutation: learning | 12/12 RED [evidence/mutation-learning.md](evidence/mutation-learning.md) |

Every test suite is mutation-tested: the thing each test guards is deliberately broken, the
test is confirmed RED, then restored and confirmed GREEN. A test that cannot fail is
deleted. This caught three cases where a mutation silently failed to apply, which proves
nothing at all, and several where a test was passing vacuously.

Formal verification uses [Halmos](https://github.com/a16z/halmos) rather than the Certora
Prover. See [ADR-007](docs/decisions/ADR-007-formal-verification-tool.md) for why.

## Deployed contracts, chain 1952

| contract | address |
|---|---|
| OrderBookVenue | [`0x7092050F3C4e72A2df8610ae2CC8c39DcA3B7f52`](https://www.oklink.com/x-layer-testnet/address/0x7092050F3C4e72A2df8610ae2CC8c39DcA3B7f52) |
| RiskGuard | [`0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24`](https://www.oklink.com/x-layer-testnet/address/0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24) |
| BatchExecutor | [`0x81beCFdE5ad4692Dc52F7eA6B9DEA0C5f1694d5e`](https://www.oklink.com/x-layer-testnet/address/0x81beCFdE5ad4692Dc52F7eA6B9DEA0C5f1694d5e) |
| RwaVault `SELF-DEPLOYED STAND-IN` | [`0x3BF12df3BB0b6f0dF8c57089ab78e402bf698F84`](https://www.oklink.com/x-layer-testnet/address/0x3BF12df3BB0b6f0dF8c57089ab78e402bf698F84) |
| RwaRiskGuard | [`0x401Ef3E4b9b838A021109c3BBebb7FDC70Cb9278`](https://www.oklink.com/x-layer-testnet/address/0x401Ef3E4b9b838A021109c3BBebb7FDC70Cb9278) |
| tBASE, tQUOTE test tokens | [`0x9D22e5...43C9`](https://www.oklink.com/x-layer-testnet/address/0x9D22e538a72a5d2c9A28D08c27999216A78343C9), [`0x7ff884...Fa0D`](https://www.oklink.com/x-layer-testnet/address/0x7ff884C412a1A2c416e931C59889e5335C5EFa0D) |

Agent-driven transactions, submitted by the runtime rather than by a script:
[`0xbed1a412`](https://www.oklink.com/x-layer-testnet/tx/0xbed1a412229db6557645a893e3465e821d5622872c8ebef8cffce3eaede80a5d),
[`0x03609244`](https://www.oklink.com/x-layer-testnet/tx/0x03609244f14d3bd14db73e46f0205ef595a9214d7af30399b090748f5ccd965f),
[`0x34bf908d`](https://www.oklink.com/x-layer-testnet/tx/0x34bf908d4fc3e23cb1be655bd47a32c6b11e4945827fcad4552ecdbd7fd7ccab)
`DEMONSTRATED`.

## Measured numbers

All measured on chain 1952, not taken from marketing material.

| metric | value |
|---|---|
| chain id | 1952 (chain 195 is deprecated and still answers, which is a trap) |
| block time | ~1.0 s, measured twice independently |
| gas limit | 210,000,000 |
| gas price | 20,000,001 wei |
| gas per agent action | 45,366 for the Ping proof, higher for multi-leg batches |
| candidates evaluated per decision | 11 to 27, generated from the live book |
| total cost of the entire build | under 0.001 OKB |

## Run it in ten minutes

Requires WSL or Linux. Foundry and Rust install from prebuilt binaries, no Docker.

```bash
# 1. toolchains
curl -L https://foundry.paradigm.xyz | bash && foundryup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# 2. build
cargo build --release
cd contracts && forge build && cd ..

# 3. tests, no chain needed
cargo test --workspace
bash scripts/10-contracts-test.sh

# 4. see it decide against the live chain, read-only, no transactions
ASML_REPO=$PWD ./target/release/asml observe 4

# 5. the AI-RWA side-by-side, the most important screen
bash scripts/24-side-by-side.sh

# 6. the dashboard
bash scripts/35-serve-ui.sh     # http://127.0.0.1:8080/ui/
```

Submitting transactions needs a funded keystore. Generate one with
`bash scripts/gen-deployer-wallet.sh`, fund the printed address from the X Layer testnet
faucet, then use `asml run <cycles>`.

## Invariants proven for all inputs

From [docs/invariants.md](docs/invariants.md) and the RWA symbolic suite:

1. No action can push per-market exposure above its cap.
2. No action can push gross exposure above the global cap.
3. Once the kill switch is set, every guarded call reverts.
4. The agent role can never clear the kill switch. Only the owner can.
5. Gross exposure always equals the sum of its per-market parts.
6. A paused RWA issuer refuses new exposure for any amount.
7. De-risking is never blocked by any RWA condition, for any amount.
8. The oracle divergence boundary is exact.
9. The RWA yield index can never decrease.
10. No caller other than the owner can loosen the RWA policy.

Property 7 is the one that matters most. A stale oracle or a paused issuer is exactly when
an agent most needs to exit, and a guard that blocks the exit turns a risk control into the
risk. It is proven symbolically, unit-tested, and demonstrated live onchain.

## Honest limitations

[docs/limitations.md](docs/limitations.md) is not a formality. The four biggest:

1. Exchange OS integration is not demonstrated, because no testnet surface exists.
2. The venue and RWA instrument are self-deployed, so their realism is bounded by what we
   wrote.
3. The coordination server stalls under a rapid burst, so its rate limiter has never been
   observed tripping. The remedy is known and stated.
4. There is no realized PnL anywhere in this project, so nothing here supports any claim
   about profitability.

## Repository layout

```
crates/          Rust workspace: 10 crates
contracts/       Solidity + Foundry: 7 contracts, 49 tests, symbolic suites
scripts/         every operation, numbered, runnable
agents/          external_agent.py, the separate-process coordination client
ui/              single-file dashboard, plus nodata-check/ proving it cannot fake data
evidence/        tx hashes, mutation tables, proof reports, gate reports per phase
docs/verified/   facts established from primary sources, with retrieval dates
docs/decisions/  ADR-001 to ADR-010
CLAUDE.md        the build's standing rules and environment facts
RESUME.md        current state, written so a fresh session can resume
```

## License

MIT.
