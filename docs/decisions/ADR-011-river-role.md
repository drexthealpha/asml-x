# ADR-011: river is a BENCHMARK, not a sidecar

Task 1.14, closing the decision gate that task 8.4 inherits. Status: ACCEPTED.
Date: 2026-08-11.

THINKING: #10 bayesian (both river's model and the hand-rolled learner update beliefs
incrementally, so they are directly comparable), #61 circle of competence (river is Python and
the brain is Rust, so "sidecar" means a live process boundary on the learning path),
#33 pareto (what does the second option buy for what it costs).

TASKS.md 1.14 states the gate explicitly: "either river becomes a sidecar the Rust learner
consults, or it is a benchmark only. Record which, and why. Do not leave it ambiguous."

## The measurement this rests on

`evidence/phase0/river.txt`, reproduce with `bash scripts/55-river-smoke.sh`:

- 79 agent decisions from `evidence/journal.jsonl`. The file has 87 rows; **8 are naive-baseline
  control rows** (thesis "naive baseline, no signals consulted") and are excluded, see the
  contamination note below.
- Features: the signals the decision engine actually used (spread_bps, imbalance_bps,
  realized_vol_bps, bid/ask depth, thesis confidence, candidate count).
- Protocol: progressive validation. Predict each row BEFORE learning from it. Learning first
  and then scoring the same row would report memorisation as skill.
- river `LogisticRegression` behind a `StandardScaler`: **0.8608** accuracy.
- Majority-class baseline: **0.8354** (66 take, 13 not-take).

river beats the baseline by 2.5 points, which on 79 samples is **two extra correct
predictions**. Stated that way because that is what it is.

### The contamination that was found, and what it changes

The first version of this benchmark scored **0.8736 against a 0.7586 baseline**, an 11.5 point
margin, and it was wrong. It included the 8 naive-baseline control rows and labelled them
not-take because their action string does not start with "take". Those rows have
`thesis_confidence_bps` of exactly 0 and no candidates, so they are trivially separable from
real decisions. The model was partly learning to tell the agent apart from its own control
group.

It was caught by a different tool, not by re-reading the script: task 1.16's DuckDB aggregation
grouped the journal by action and put a row reading `Buy 2.000000 base, 8 decisions, avg_conf 0`
on screen next to the others. That is the argument for making every tool touch real data rather
than a smoke fixture.

Corrected numbers are above. The margin fell from 11.5 points to 2.5, which makes the decision
below stronger rather than weaker.

## Decision

**Benchmark only.** river does not run in the product. It stays a measurement tool used
against the journal.

## Why, including the part that weakens the case for river

The number above is honest about accuracy and misleading about usefulness, and the reason is
in the target variable. The journal carries no realized PnL until task 8.5, so the only
learnable target today is BEHAVIOUR: did the agent take. river is therefore predicting the
decision engine's own output from the decision engine's own inputs. A deterministic scoring
function is a nearly-learnable function by construction. 0.8608 measures how closely a linear
model can imitate `score_take`, not how well anything predicts profit. And once the control
rows are removed, it beats always-guessing-take by two predictions out of 79.

That reframing settles the gate. A sidecar's job would be to improve decisions, and a model
trained to imitate the existing decision cannot improve it. Making it a sidecar would add a
Python process on the learning path, a serialisation boundary, and a failure mode where the
brain waits on a model that has nothing to add.

Two further reasons, stated plainly:

1. **Sample size.** 87 rows. The clamped update in `crates/learning` was chosen at this sample
   size for the same reason task 1.10 rejected drift detectors: at this volume a detector or a
   fitted model fires on noise. Adding a second learner does not add data.
2. **The learning safety property.** `Learner` has no type mentioning `Limits`, which is what
   makes "learning cannot widen a limit" a structural fact rather than a promise. A Python
   sidecar returning a JSON blob that influences the learner is a place where that structure
   has to be re-established by hand, and hand-maintained invariants are the ones that break.

## What river IS used for, so this is not a discard

It is the external check on the hand-rolled learner. When 8.5 lands realized PnL in the
journal, the same script re-runs against the profit target and answers a question the internal
learner cannot answer about itself: is there signal in these features at all. If river cannot
beat the baseline on the profit target, then neither can the Rust learner, and that is a
finding about the features rather than about either implementation.

## THE FALSIFICATION TEST WAS RUN. Result, 2026-08-16, task 14.5

Task 8.5 became 14.4 and landed realized PnL, so the test below could finally be run instead of
deferred again. `evidence/phase14/river-profit.txt`, reproduce with
`bash scripts/172-river-profit-target.sh`:

- 8 settlements, 1 orphaned and dropped, **7 usable samples**.
- Class balance: 3 profitable, 4 not.
- river progressive-validation accuracy **0.5714**. Majority-class baseline **0.5714**.
- Margin: **+0.0 points, zero extra predictions.** One-sided binomial p = 0.6531.

**The condition is NOT met and this ADR stands unchanged: river remains a benchmark.** river did not
beat the baseline by so much as a single prediction, which is the outcome this ADR anticipated, and
it is a finding about the FEATURES rather than about either implementation.

**The caveat matters more than the number.** These labels are INDUCED. This venue's book is static,
so nothing settles on its own; `scripts/171-build-pnl-sample.sh` posts real orders that move the mid,
and the profit label follows from which way it was moved. The target is therefore a function of the
sampling procedure, not of a market. **A win would not have licensed reopening the sidecar question
either**, and the evidence file says so before reporting the number rather than after.

So the honest reading is that this ADR asked for a measurement only an exogenous market can supply,
and this harness cannot supply one. The test is recorded as run, with 7 samples and its limits
attached, rather than left open a second time.

## Falsification test

This ADR should be revisited if, after 8.5, river beats the majority baseline on a REALIZED
PROFIT target by a margin that survives the sample size. At that point the sidecar question is
live again, because the model would be predicting something the decision engine does not
already know. Until that measurement exists, sidecar integration would be a dependency added
on the strength of a metric that measures self-imitation.
