# Research basis

Task 1.10. Each entry states what was taken from the literature and whether it is
IMPLEMENTED in the scoring path or CONSIDERED-REJECTED with the reason. Rejections are kept
deliberately: papers read and rejected show judgement, and hiding them would misrepresent
how the scoring function was chosen.

Corpus pulled with paperscraper (arxiv backend). Raw query output in
evidence/phase0/paperscraper.txt.

## Papers actually retrieved and used (titles from this run, not from memory)

- "Trading in the Sunshine or in the Shade: Market Impact and Adverse Selection on
  Hyperliquid" (2026-06-14). Directly on-topic: adverse selection measured on a live
  perp DEX order book, which is the closest published setting to this agent's venue.
- "Market Simulation under Adverse Selection" (2024-09-19).
- "Latency and liquidity provision in a limit order book" (2015-11-12).
- "Detecting and Adapting to Irregular Distribution Shifts in Bayesian Online Learning"
  (2020-12-15).
- "Sample-Mean Anchored Thompson Sampling for Offline-to-Online Learning with Distribution
  Shift" (2026-05-11).
- "Market Making in Spot Precious Metals" (2024-04-23).

Full query output, including the two queries per topic and all 15 records, is in
evidence/phase0/paperscraper.txt.

## IMPLEMENTED: adverse selection is a cost a taker pays, not an edge it earns

The v1 scoring function initially credited a taker with a fraction of the observed spread.
That is backwards, and the market-making literature is unambiguous about why: the spread is
compensation to the LIQUIDITY PROVIDER for inventory risk and adverse selection. A taker
crossing the spread pays that compensation.

Applied in `crates/decision-engine/src/lib.rs`, `score_take`:
  - a taker's edge is DIRECTIONAL only, derived from damped depth imbalance
  - the half-spread is charged as an explicit `crossing_cost` term
  - the imbalance forecast is scaled by that signal's own confidence

Evidence that this changed behaviour: before the correction the agent held on every live
cycle and looked prudent; after it, it sells into ask-heavy books for a stated reason. See
evidence/gates/phase-4.md.

## IMPLEMENTED: inventory risk grows with position, so variance is penalised by size

The variance term scales with notional rather than being a flat penalty, which follows the
standard inventory-risk result that the cost of holding grows with the position held.

Applied in `score_take` as `variance_penalty`, proportional to realized volatility and
notional.

## CONSIDERED-REJECTED: closed-form optimal quoting under inventory constraints

Rejected for this build. The closed-form results assume a continuous quoting process with a
known terminal horizon. This agent takes discrete liquidity against a self-deployed venue
with roughly 110 user transactions per 300 blocks, so the model's central assumption does not
hold here. Adopting the formula would have produced a precise-looking number resting on an
assumption the venue violates.

## CONSIDERED-REJECTED: drift-detection triggers for the learning rate

Rejected on sample size. Drift detectors need a data volume this build does not have: the
learning layer settles single-digit-to-low-double-digit outcomes. A detector on that many
samples would fire on noise. The clamped update in `crates/learning` is the honest choice at
this sample size, and the sample size is disclosed everywhere the learning claim appears.
