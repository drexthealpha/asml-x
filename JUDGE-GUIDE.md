# Judge guide

**Seven minutes, in order.** Each step says what to look at, and what would falsify it.

If you have ninety seconds, do **step 1 and step 2**. Those are the two claims everything else
supports: this is live on X Layer mainnet with real money, and a person can actually use it.

Every claim below is tagged `[C-xxx]` and resolves to a row in
[evidence/CHAIN-OF-EVIDENCE.md](evidence/CHAIN-OF-EVIDENCE.md) carrying the artifact and the command
that regenerates it. 119 rows. To check the whole index at once:

```bash
bash scripts/44-chain-verify.sh
```

---

## 1. It is live on X Layer mainnet, with the user's own money — 90 seconds

Not a testnet demo. **Chain 196, real OKB.** Verify it without trusting a single file in this repo:

```bash
bash scripts/184-mainnet-reverify.sh
```

That script scrapes the hashes and addresses **out of the evidence documents** and checks them
against chain 196, so a document that quietly changed a hash fails rather than being confirmed by a
constant somebody updated to match. `[C-1602]`

**What you should see:** `eth_chainId` 196; 7 transactions each checked against **what its own
document claims**; 7 contracts carrying real bytecode; and live contract state showing
`chargeCount` 1, a treasury address **distinct from the deployer**, and a solvent vault.

**The detail worth pausing on:** one of those 7 transactions is expected to **revert**, and does. It
is the proof that the risk gate refuses an over-cap trade **with real money at stake** `[C-1201]`. A
version of this checker that expected success everywhere would have flagged the single most
important negative result in the project as a defect.

The whole mainnet launch cost **0.000203652 OKB across 75 transactions**, reconciled against the
deployer's balance delta rather than summed from a table of plausible figures. **No USD figure is
asserted anywhere**: the chain cannot be asked what OKB is worth `[C-1205]`.

---

## 2. A person can deposit, let the agent trade, and get their money back — 2 minutes

This is the product. Everything else is what makes it safe to use.

```bash
bash scripts/serve-ui.sh
```

Open the dashboard. **You do not need a wallet to see it work**: press **Run full demo** on the
landing page. It runs a complete cycle against the live chain and shows the thesis, the candidates
scored, the risk verdict and the transaction. It is not a replay — a replay would leave the journal
length unchanged, and the endpoint refuses to return success if it does `[C-905]`.

With a wallet, the full path is **deposit → the agent acts under a limit you set → withdraw**, and it
was executed on mainnet end to end: 5 in, 5 out, vault left solvent with the user's balance at zero
`[C-1204]`.

Connect to running takes a measured **8.6s median across three cold runs**, first paint to activated.
That figure is labelled **scripted, not human** — a script does not hesitate and a person does, so
treat it as a lower bound `[C-1001]`.

**What makes it non-trivial:** the limit you set can only ever *tighten* what the agent may do.
`Limits::tightened_by` takes the minimum of each field, so a user limit cannot widen a system limit
even if the caller asks it to. And **pause can never block withdrawal** — that is proved as an
invariant, not promised in a comment `[C-1401]`.

---

## 3. Risk refuses, and the refusal is legible — 90 seconds

```bash
ASML_REPO=$PWD ./target/release/asml observe 4
```

Four cycles against live chain 1952: block number, live orders read from chain, a candidate count
that *changes with the book* because candidates are generated from live state rather than picked
from a fixed menu, the chosen action, and the risk verdict.

Every refused candidate carries **its own numbers and its reason**, not a generic rejection. And the
same cap rule is enforced in **three independent implementations** — the live deployed contract,
the same bytecode replayed in revm, and the Rust risk engine — which are shown to agree on the
**revert selector and its decoded arguments**, not merely on a boolean `[C-1400]`:

```bash
bash scripts/164-differential-proof.sh
```

Two implementations that both refuse *for different reasons* have coincided, not agreed. The
under-cap call succeeding in the same run is the control, without which a contract that reverted on
everything would pass.

---

## 4. The honest result: the agent's signal is worse than a coin flip — 60 seconds

**This is on the landing page, in the loss colour, with its sample size.** It is not buried.

- Signal hit rate **40.0%, n = 10**. Below a coin flip.
- The learner responded by cutting `momentum_weight_bps` from its default of **2000 to 391** and
  raising `thin_book_penalty_bps` from **150 to 1225** — until the agent stopped taking positions
  and chose `hold`. `[C-1406]`
- Realized PnL is recorded **in money, not just direction**: decision 176 predicted down, the mid
  moved against it, and it settled to **−37,500 micro quote** `[C-1403]`.

**What is claimed:** outcomes are measured, attributed to the decision that produced them, and acted
on. **What is not claimed:** profitability. Ten settled outcomes is not a track record, and the
realized figure is mark-to-market against a later observed mid, not cash from a closing trade.

Every figure carries its sample size **because the data structure forces it** — the count lives
inside the same object as the value, so a component cannot render the number without it.

---

## 5. It refuses hostile callers, on the deployed bytecode — 60 seconds

```bash
bash scripts/178-adversarial-fee-vault.sh
```

Nine hostile calls from an address this project holds no key for, each matched against the **exact
error selector** rather than a name, because an X Layer node returns custom errors as raw calldata
and "it reverted" and "it reverted for the reason I claimed" are different findings `[C-1500]`.

Three negative controls run **as the same attacker** and succeed. Without them, a contract that
reverted on everything would score a perfect refusal rate.

This runs against **what is actually deployed**, not locally compiled bytecode. A contract can pass
its own test suite and not be the contract that reached the chain.

---

## 6. Reproduce the whole thing — 60 seconds

```bash
bash scripts/183-reproduce.sh
```

Nine gates including the full Rust workspace and 113 contract tests `[C-1600]`.

That reproduction audit found **three defects in the evidence chain itself** and repaired them: a
duplicate claim id that made `[C-710]` ambiguous, and two rows citing scripts that never existed
`[C-1601]`. It runs an inventory pass *before* any re-execution, because a row citing a missing file
produces a runner failure indistinguishable from a flaky test.

All **33 fake wins named in TASKS.md** have a claim covering their subtask `[C-1603]`. The register
prints each claim's text and deliberately **refuses to score whether the refusal is convincing** — a
script asserting that thirty traps were avoided, written by the same process that might have fallen
into them, would be that task's own fake win.

---

## 7. What this project does not claim

Stated here so you do not have to go looking.

- **Not profitable.** See step 4. The measured signal is worse than a coin flip on 10 samples.
- **The venue and the RWA vault are self-deployed stand-ins**, labelled as such everywhere. This is
  not integrated with a real order book.
- **AggLayer settlement is INFERRED, not verified.** Reading chain 196's deployed bytecode found a
  standard OP Stack bridge stack and no AggLayer path visible from L2 at all. The chain *is* past
  Ecotone and Fjord, demonstrated by `eth_call`. This is stated because an earlier version of the
  internal notes asserted it, and the assertion did not survive being checked.
- **The mid moves because this project moves it.** The seeded book is static, so nothing settles on
  its own. The profit labels used to benchmark the learner are **induced** by a script that posts
  real orders. A win there would not have licensed a stronger claim, and the evidence file says so
  *above* its numbers `[C-1405]`.
- **The coordination fee is quoted, not charged.** The API has no identity system behind its key.
- **The trace exports to stdout, not to a collector.** Real OpenTelemetry SDK, real span tree, no
  infrastructure to stand up `[C-1402]`.

---

## The fastest way to attack this submission

If you want to break it, these are the places I would look, in order:

1. **The sample sizes.** n = 10 on the learning result. Everything in step 4 is honest about this,
   but it is genuinely small, and no amount of framing changes that.
2. **The stand-in venue.** The agent trades against a book this project deployed and seeds. The
   decisions are real and the transactions are real; the *market* is not adversarial.
3. **The induced profit labels.** Step 7 covers it. If you disagree that this was worth doing at
   all, that is a fair position — it exercises a code path that would otherwise never run.
4. **Anything asserting AggLayer.** There should be nothing. If you find a claim that AggLayer
   settlement was verified, it is a bug and I want it cut.

Two ADRs in `docs/decisions/` were **rewritten against their own author** when the measurements came
back wrong: ADR-018, where a mobile-layout emergency turned out to be my own measurement code
ignoring scroll clipping, and ADR-019, where "crates.io is unreachable from this machine" was
asserted without ever being tested and was simply false. Both are left in the repo with the
correction attached rather than quietly fixed.
