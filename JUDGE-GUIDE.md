# Judge guide

Five minutes, in order. Each step names what to look at and what would falsify the claim.

If you only have sixty seconds, do step 2 and step 4.

---

## 0. Setup, one minute

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
cargo build --release
```

No Docker, no API keys, no wallet extension. Everything below except transaction
submission is read-only against public infrastructure.

---

## 1. The agent decides against the live chain, 60 seconds

```bash
ASML_REPO=$PWD ./target/release/asml observe 4
```

**What you should see:** four cycles, each reporting the block number, the number of live
orders read from chain 1952, a candidate count between 11 and 27, the chosen action, a
thesis with a confidence in basis points, and the risk verdict.

**What makes it non-trivial:** the candidate count changes with the book, because
candidates are generated from live state rather than picked from a fixed menu. The thesis
sentence is assembled from the actual signal numbers.

**How to falsify it:** point it at the wrong chain. It refuses to start on anything except
chain 1952 and names 195 as the deprecated testnet.

---

## 2. Risk actually stops the agent, and you can see it onchain

This is the claim most worth checking, so check it two ways.

**Offchain, in the candidate record.** Open [ui/index.html](ui/index.html) after step 5, or
read `evidence/journal.jsonl`. The risk panel groups refusals by reason. In the recorded run
`OrderNotionalTooLarge` appears 40 times, meaning the engine wanted to trade larger and was
refused.

**Onchain, in the RWA guard.** Read
[evidence/rwa-live/live-triggers.txt](evidence/rwa-live/live-triggers.txt). It walks four
refusal conditions live with transaction hashes:

- issuer pause set, `addExposure` REFUSED(IssuerPaused)
- **de-risk while paused, `reduceExposure` ACCEPTED**, tx `0xd2ae42fd`
- oracle diverged 1000 bps, REFUSED(OracleMarketDivergence)
- oracle aged past its threshold, REFUSED(OracleStale)
- redemption window inside the buffer, REFUSED(RedemptionWindowTooClose)

**The line to look at is the second one.** Adding is refused while exiting still works. A
guard that blocks the exit when the oracle is stale converts a risk control into a trap.
That asymmetry is proven three ways: symbolically for all amounts
(`check_reduceIsNeverBlockedByRwaConditions`), by unit test, and live onchain.

**How to falsify it:** run `bash scripts/25-rwa-mutation.sh`. It removes each refusal in
turn and confirms the tests go RED. 18 of 18 RED means no refusal is decorative.

---

## 3. The AI-RWA side-by-side, 90 seconds

```bash
bash scripts/24-side-by-side.sh
```

The same order, the same live signals, evaluated against a pure crypto market and an
RWA-linked market, across four instrument states. Output is also saved at
[evidence/rwa-live/side-by-side.txt](evidence/rwa-live/side-by-side.txt).

| state | crypto market | RWA market |
|---|---|---|
| healthy | APPROVED | APPROVED |
| issuer paused | APPROVED | REFUSED `RwaIssuerPaused` |
| oracle diverged 1200 bps | APPROVED | REFUSED `RwaOracleMarketDivergence{1200,300}` |
| restored | APPROVED | APPROVED |

**The healthy row is the important one.** Without it, the RWA layer could be a global brake
wearing an RWA label. With it, the refusals are demonstrably specific to the instrument and
its current state. The onchain `rwaTradeableFlag()` agreed with the offchain engine in every
case.

---

## 4. A real transaction, driven by the agent

Three transactions submitted by the runtime itself, not by a script:

- [`0xbed1a412…`](https://www.oklink.com/x-layer-testnet/tx/0xbed1a412229db6557645a893e3465e821d5622872c8ebef8cffce3eaede80a5d)
- [`0x03609244…`](https://www.oklink.com/x-layer-testnet/tx/0x03609244f14d3bd14db73e46f0205ef595a9214d7af30399b090748f5ccd965f)
- [`0x34bf908d…`](https://www.oklink.com/x-layer-testnet/tx/0x34bf908d4fc3e23cb1be655bd47a32c6b11e4945827fcad4552ecdbd7fd7ccab)

Each is a multi-leg atomic batch through `BatchExecutor`: the risk guard leg runs first, so
a cap breach or a halt reverts the whole batch before any token moves. Guard exposure moved
4.0e18 to 10.075e18 across the three, with `gross() == sumOfParts()` holding throughout.

Full context, including how the agent adapted as its own fills moved the book (imbalance
3750 to 5172 to 6296 bps, a different order and size each cycle), is in
[evidence/gates/phase-4.md](evidence/gates/phase-4.md).

---

## 5. The dashboard, and proof it cannot fake data

```bash
bash scripts/35-serve-ui.sh
```

- Dashboard: <http://127.0.0.1:8080/ui/>
- **No-data proof: <http://127.0.0.1:8080/ui/nodata-check/>**

The second link is the same page in a directory where its data files do not resolve. Every
panel reports "not readable" or "runtime has not run", with red borders, and the numbers
read 0 and n/a. A dashboard that shows plausible values with no data behind it is the
standard way this kind of demo lies, so the failure mode is shipped as a checkable artifact.

On the dashboard itself, the candidate table shows the chosen action and every rejected
alternative with all four score terms, which is the evidence that a search happened rather
than an if/else ladder running.

---

## 6. Where the code enforces its own rules, 60 seconds

Three things are enforced by the compiler or the prover rather than by discipline.

**The agent cannot bypass the risk gate.** Signing requires a `RiskApproved<OrderIntent>`,
whose only constructor is inside the risk engine. Attempting to forge one does not fail a
test, it fails to compile:
[evidence/bypass-compile-error.txt](evidence/bypass-compile-error.txt).

**Learning cannot widen a risk limit.** `Learner` has no type in its API that mentions
`Limits`. It emits scoring parameters only. See `crates/learning/src/lib.rs`.

**The limits are proven, not sampled.** 14 Halmos theorems across the base guard and the
RWA guard, each proven for all inputs in range. Verify the proofs can fail:

```bash
bash scripts/16-proof-mutation.sh   # injects a 1-wei cap violation, prover catches it
bash scripts/21-rwa-formal.sh       # removes the pause refusal, prover catches it
```

---

## 7. What this project does not claim

Please read [docs/limitations.md](docs/limitations.md). Summary:

- **Exchange OS integration is not demonstrated.** It has no developer surface on X Layer
  testnet, established by four primary probes. It is a labelled forward commitment.
- **The venue and the RWA instrument are self-deployed** and labelled as such everywhere.
  Chain 1952 had nothing liquid to integrate against.
- **No realized PnL.** Nothing here supports a claim about profitability.
- **The coordination server stalls under a rapid burst**, so its rate limiter has never been
  observed tripping. The remedy is stated.
- **Learning sample sizes are single digits.** The mechanism is proven, the improvement is
  not.

---

## The fastest way to attack this submission

If you want to find the weak points, these are where they are, and each is already
documented rather than hidden:

1. Ask what happens when Exchange OS opens. Answer:
   [docs/mainnet-path.md](docs/mainnet-path.md), and the venue interface is two calls wide.
2. Point out the venue is self-dealing. Correct, and stated in
   [ADR-001](docs/decisions/ADR-001-venue-strategy.md) with the evidence that forced it.
3. Ask for the learning improvement number. There isn't one, and
   [evidence/gates/phase-7.md](evidence/gates/phase-7.md) says so.
4. Burst the coordination endpoint. It will stall, and
   [evidence/gates/phase-6.md](evidence/gates/phase-6.md) predicts that.
