# Demo script, three minutes, one take

Task 18.1. THINKING: #53 phenomenological (what does a viewer actually take away), #12 design
thinking, #33 prioritisation.

**The shape:** land, connect, see the defaults, deposit, activate, watch a decision and a fee event,
pause, withdraw, then toggle to the Terminal view for depth.

**One take, no cuts that hide a failure.** If something reverts or a read fails on camera, keep it
and say what it is. A demo edited to remove a refusal is advertising the opposite of what this
project claims. The risk gate refusing is a feature and it is on camera deliberately at 1:45.

---

## Before recording

```bash
bash scripts/136-seed-executable-book.sh   # a book worth trading, so the agent acts rather than holds
bash scripts/88-recompute-metrics.sh       # counters current
cd ui-v2 && pnpm build && cd ..
bash scripts/serve-ui.sh
```

Hard-reload the page before rolling. A stale bundle is the single most likely thing to make this
recording wrong, and it has already happened once in this project: a measurement returned numbers
identical to the baseline because the browser was serving an old build.

Have the wallet already installed and holding testnet tQUOTE, but **not yet connected**. The cold
connect is part of the demo.

---

## 0:00 — 0:20 | Land

**On screen:** the landing page, YOU tab, untouched.

**Say:** "This is an agent that trades your money under limits you set. The first thing you see is
your wallet and your position, not a chart."

**Point at:** the MAINNET panel in the left column. "It is already running on X Layer mainnet, chain
196, with real OKB. Those are real transaction hashes and each one opens in the explorer."

Do not scroll yet.

---

## 0:20 — 0:40 | Connect

**Do:** press Connect. Approve in the wallet.

**Say:** "Connect is a real EIP-1193 provider, not local state. If the wallet is on the wrong
network the page says so rather than pretending."

**On screen:** the position panel replaces its empty state with a real balance.

---

## 0:40 — 1:05 | The defaults, before any money moves

**Say:** "Before depositing, these are the limits. The important property is that the limit you set
can only ever tighten what the agent may do. `Limits::tightened_by` takes the minimum of each field,
so a user limit cannot widen a system limit even if the caller asks."

**Point at:** the fee disclosure. "Forty-nine basis points, read from the deployed contract, not
hardcoded in the page. The rate can only ever fall."

> **This beat only exists after Connect succeeds.** The disclosure lives in `activate.tsx:310` and
> renders from `pos.feeBps`, read live. On a disconnected page it is not on screen at all, so do not
> try to point at it before 0:20. Verified by beat check: 9 of 10 beats confirmed on the live page,
> and this is the one that cannot be confirmed without a wallet.

---

## 1:05 — 1:25 | Deposit

**Do:** deposit. Approve in the wallet.

**Say:** "This is a permit-based deposit, so it is one signature and one transaction rather than
approve-then-deposit."

**On screen:** the balance updates from the chain.

---

## 1:25 — 2:00 | Activate, watch a decision and a fee event

**Do:** activate the agent. Then press **Run full demo**.

**Say:** "One cycle: it reads the order book from chain, forms a thesis from the measured signals,
generates a candidate set, scores every candidate, and puts the winner through the risk gate."

**On screen:** thesis, candidate count, chosen action, transaction hash, fee event.

**Say, pointing at a refused candidate:** "Every refusal carries its own numbers and its reason, not
a generic rejection. And this is the part worth watching —"

**If a refusal appears on camera, stop and name it.** "That candidate was refused because it
exceeded the per-market cap. The same cap is enforced in three places: this engine, the deployed
contract, and the same bytecode replayed in an in-memory EVM. They agree on the revert selector and
its decoded arguments, not just on a yes or no."

---

## 2:00 — 2:20 | The honest number

**Do:** scroll to **What the agent learned**.

**Say:** "This is the part most demos would hide. The signal's hit rate is forty percent on ten
settled outcomes. That is worse than a coin flip."

**Point at:** the net move. "The learner noticed, and cut the momentum weight from two thousand to
three hundred and ninety-one, until the agent stopped taking positions. That is the loop working.
What is claimed is that outcomes are measured and acted on. Not that it makes money."

**Point at:** `n = 10` in the panel header. "Every figure carries its sample size, because the data
structure forces it: the count lives inside the same object as the value."

---

## 2:20 — 2:40 | Pause and withdraw

**Do:** pause the agent. Then withdraw.

**Say:** "Pause stops the agent. It does **not** stop you withdrawing — that is proved as an
invariant over a hundred and twenty-eight run campaign, and the campaign is shown able to fail by
breaking the thing it guards and watching exactly one invariant go red."

**On screen:** balance returns to the wallet.

---

## 2:40 — 3:00 | Terminal view, for depth

**Do:** switch to CHAIN.

**Say:** "Everything under it is checkable. A hundred and twenty-four claims, each with the artifact
and the command that regenerates it. Nine hostile calls refused by the deployed bytecode. Every
mainnet claim re-verified from chain rather than from any file in the repository."

**Close on:** the transaction list.

---

## What must NOT be said

- Any figure in USD. The chain cannot be asked what OKB is worth.
- "Profitable", "returns", "yield", or anything implying performance.
- "Verified" about AggLayer settlement. It is INFERRED.
- "Integrated with Exchange OS." There is no developer surface to integrate with.
- Anything about the venue that does not carry "self-deployed stand-in" nearby.
