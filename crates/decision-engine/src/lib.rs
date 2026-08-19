//! The decision engine. Task 4.2.
//!
//! The design constraint that matters: this is a scored search over a generated
//! candidate set, not an if/else ladder wearing a scoring function. Concretely
//!
//! - candidates are GENERATED from the live book, so the set differs run to run,
//! - every candidate is scored on four competing terms, not one,
//! - the full set including rejects is persisted with per-term breakdowns,
//! - "do nothing" is always a real candidate that can win on merit,
//! - the engine never sees a signal without its confidence, and low confidence
//!   shrinks size rather than being ignored.
//!
//! A test asserts the evaluated candidate count is never 1, because a search with
//! one option is not a search. That is the anti-fake-win guard for this phase.

use core_types::{InstrumentKind, MarketId, Micro, OrderIntent, Portfolio, Side, MICRO};
use journal::CandidateRecord;
use market_intel::{Estimate, Signals};
use risk_engine::{Limits, RiskApproved, RiskContext, RiskEngine};

/// What the agent could do, expressed against the venue's actual primitives.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// Deliberately hold. A real option, scored like any other.
    Hold,
    /// Take liquidity from a resting order.
    Take {
        order_id: u64,
        side: Side,
        base_amount: Micro,
        price_quote: Micro,
    },
    /// Post a resting quote.
    Post {
        side: Side,
        base_amount: Micro,
        price_quote: Micro,
    },
}

impl Action {
    #[must_use]
    pub fn label(&self) -> String {
        match self {
            Action::Hold => "hold".to_string(),
            Action::Take {
                order_id,
                side,
                base_amount,
                price_quote,
            } => format!(
                "take order {order_id} {side:?} {} base at {}",
                market_intel::fmt_micro(*base_amount),
                market_intel::fmt_micro(*price_quote)
            ),
            Action::Post {
                side,
                base_amount,
                price_quote,
            } => format!(
                "post {side:?} {} base at {}",
                market_intel::fmt_micro(*base_amount),
                market_intel::fmt_micro(*price_quote)
            ),
        }
    }

    /// The order intent this action implies, if any. `Hold` has none, which is
    /// why the risk gate is asked only about actions that would touch the chain.
    #[must_use]
    pub fn to_intent(
        &self,
        market: &MarketId,
        kind: InstrumentKind,
        decision_id: u64,
    ) -> Option<OrderIntent> {
        match self {
            Action::Hold => None,
            Action::Take {
                side,
                base_amount,
                price_quote,
                ..
            }
            | Action::Post {
                side,
                base_amount,
                price_quote,
            } => Some(OrderIntent {
                market: market.clone(),
                kind,
                side: *side,
                size_micro: *base_amount,
                limit_price_micro: *price_quote,
                decision_id,
            }),
        }
    }
}

/// A scored candidate. Every term is kept separately so the journal can show WHY
/// one beat another, rather than only that it did.
#[derive(Debug, Clone)]
pub struct Candidate {
    pub action: Action,
    pub expected_edge_micro: Micro,
    pub variance_penalty_micro: Micro,
    pub capital_cost_micro: Micro,
    pub execution_risk_penalty_micro: Micro,
    pub rejection_reason: Option<String>,
}

impl Candidate {
    #[must_use]
    pub const fn score_micro(&self) -> Micro {
        self.expected_edge_micro
            - self.variance_penalty_micro
            - self.capital_cost_micro
            - self.execution_risk_penalty_micro
    }

    fn to_record(&self, chosen: bool) -> CandidateRecord {
        CandidateRecord {
            label: self.action.label(),
            score_micro: self.score_micro(),
            expected_edge_micro: self.expected_edge_micro,
            variance_penalty_micro: self.variance_penalty_micro,
            capital_cost_micro: self.capital_cost_micro,
            execution_risk_penalty_micro: self.execution_risk_penalty_micro,
            chosen,
            rejection_reason: self.rejection_reason.clone(),
        }
    }
}

/// Tunable weights. These are what the Learning Agent adjusts in Phase 7.
///
/// Note what is absent: no risk limit appears here. Limits live in `Limits`, which
/// this struct cannot reach, so learning structurally cannot widen one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Params {
    /// How much of the observed depth imbalance is treated as a directional
    /// forecast, in basis points. This is the only source of edge for a taker.
    pub momentum_weight_bps: u32,
    /// Penalty applied per basis point of realized volatility, scaled by size.
    pub variance_weight_bps: u32,
    /// Assumed cost of capital per unit notional, basis points.
    pub capital_cost_bps: u32,
    /// Penalty for taking a large fraction of a thin order, basis points.
    pub thin_book_penalty_bps: u32,
    /// Below this confidence, size is scaled down proportionally.
    pub min_confidence_bps: u32,
    /// Largest fraction of a resting order to take at once, basis points.
    pub max_take_fraction_bps: u32,
}

impl Default for Params {
    fn default() -> Self {
        Self {
            momentum_weight_bps: 2_000,
            variance_weight_bps: 8_000,
            capital_cost_bps: 20,
            thin_book_penalty_bps: 150,
            min_confidence_bps: 3_000,
            max_take_fraction_bps: 5_000,
        }
    }
}

pub struct DecisionEngine {
    pub params: Params,
    pub market: MarketId,
    pub kind: InstrumentKind,
}

/// The outcome of one decision cycle.
pub struct Decision {
    pub candidates: Vec<Candidate>,
    pub chosen_index: Option<usize>,
    pub approved: Option<RiskApproved<OrderIntent>>,
    pub risk_verdict: String,
}

impl Decision {
    #[must_use]
    pub fn chosen(&self) -> Option<&Candidate> {
        self.chosen_index.and_then(|i| self.candidates.get(i))
    }

    #[must_use]
    pub fn records(&self) -> Vec<CandidateRecord> {
        self.candidates
            .iter()
            .enumerate()
            .map(|(i, c)| c.to_record(Some(i) == self.chosen_index))
            .collect()
    }
}

impl DecisionEngine {
    #[must_use]
    pub fn new(market: MarketId, kind: InstrumentKind, params: Params) -> Self {
        Self {
            params,
            market,
            kind,
        }
    }

    /// Generate candidates from the live book.
    ///
    /// The set is data-dependent: more resting orders produce more take candidates,
    /// at several sizes each. This is what makes the search real rather than a fixed
    /// menu, and it is why the candidate count varies between cycles.
    #[must_use]
    pub fn generate(&self, signals: &Signals, book: &[market_intel::OrderView]) -> Vec<Candidate> {
        // No budget: every existing caller and every Phase 4 to 10 artifact behaves exactly as
        // before. Affordability is opt-in so nothing that already reproduces stops reproducing.
        self.generate_within(signals, book, None)
    }

    /// Generate candidates the portfolio can actually PAY FOR.
    ///
    /// WHY THIS EXISTS. Sizes came from `order.remaining_base()`, which is the resting size on the
    /// venue. That is a fine basis for "what could be taken" and a useless one for "what can be
    /// afforded": with a real balance of 0.198978 USDT the engine kept proposing orders worth one
    /// to two whole quote units, the risk gate refused all twenty-four of them, and the agent
    /// looked broken while behaving correctly. The size a candidate proposes has to be bounded by
    /// the money that exists, or every cycle is spent generating options and rejecting them.
    ///
    /// This is also the difference between a fixed menu and live generation: with a budget the
    /// same book yields different candidates as the balance moves, which is what makes the agent
    /// tradable with one dollar rather than needing a hundred.
    ///
    /// SHRINK ONLY, NEVER GROW. The budget can reduce a size and can drop a candidate entirely.
    /// It can never raise one above what the book offers, so it cannot manufacture an opportunity
    /// that the market is not showing. That direction matters: a bound that could widen would be a
    /// second way to authorise a trade, and the risk gate is supposed to be the only one.
    #[must_use]
    pub fn generate_within(
        &self,
        signals: &Signals,
        book: &[market_intel::OrderView],
        budget_quote_micro: Option<i128>,
    ) -> Vec<Candidate> {
        let mut out = vec![self.score_hold(signals)];

        let confidence = signals
            .spread_bps
            .as_ref()
            .map_or(0, Estimate::confidence_bps);

        for order in book.iter().filter(|o| o.is_live()) {
            let remaining = order.remaining_base();
            // Several sizes per order, so size is chosen rather than assumed.
            for frac_bps in [2_500u32, 5_000, 10_000] {
                if frac_bps > self.params.max_take_fraction_bps {
                    continue;
                }
                let mut amount = (remaining * i128::from(frac_bps)) / 10_000;
                // Low confidence shrinks size rather than being ignored.
                if confidence < self.params.min_confidence_bps {
                    amount = (amount * i128::from(confidence.max(1)))
                        / i128::from(self.params.min_confidence_bps.max(1));
                }
                if amount <= 0 {
                    continue;
                }
                // Taking from a maker who buys base means we sell base.
                let side = if order.maker_buys_base {
                    Side::Sell
                } else {
                    Side::Buy
                };

                // AFFORDABILITY, applied to buys only. A buy spends the quote asset, so it is
                // bounded by the quote balance. A sell spends BASE, which this budget says nothing
                // about, and clamping it against a quote figure would silently forbid selling an
                // inventory the agent already holds.
                if let (Some(budget), Side::Buy) = (budget_quote_micro, side) {
                    if order.price_quote <= 0 {
                        continue;
                    }
                    // Integer throughout. `max_affordable` is the base size whose notional fits
                    // inside the budget; truncation rounds DOWN, so it can never round into an
                    // order that cannot be paid for.
                    let max_affordable = (budget * MICRO) / order.price_quote;
                    amount = amount.min(max_affordable);
                    if amount <= 0 {
                        // Not a failure and not silence: the budget genuinely cannot buy the
                        // smallest unit at this price, so there is no candidate to score.
                        continue;
                    }
                }
                out.push(self.score_take(
                    signals,
                    order.id,
                    side,
                    amount,
                    order.price_quote,
                    remaining,
                ));
            }
        }

        out
    }

    fn score_hold(&self, _signals: &Signals) -> Candidate {
        // Holding scores exactly zero: no edge, no cost. That makes the decision
        // rule interpretable, because any action that wins must have a positive
        // risk-adjusted expected value in its own right rather than merely being
        // less bad than the alternatives.
        Candidate {
            action: Action::Hold,
            expected_edge_micro: 0,
            variance_penalty_micro: 0,
            capital_cost_micro: 0,
            execution_risk_penalty_micro: 0,
            rejection_reason: None,
        }
    }

    /// Expected price move in basis points, signed. Positive means up.
    ///
    /// Derived from depth imbalance: more resting bids than asks means buyers are
    /// more eager, and the taker who buys is on the right side of that. Damped by
    /// `momentum_weight_bps` because imbalance is a weak forecast, and scaled by the
    /// imbalance estimate's own confidence so a two-order book does not produce a
    /// confident forecast.
    fn expected_move_bps(&self, signals: &Signals) -> i128 {
        signals.imbalance_bps.as_ref().map_or(0, |imb| {
            let damped = (imb.value * i128::from(self.params.momentum_weight_bps)) / 10_000;
            (damped * i128::from(imb.confidence_bps())) / 10_000
        })
    }

    fn score_take(
        &self,
        signals: &Signals,
        order_id: u64,
        side: Side,
        base_amount: Micro,
        price_quote: Micro,
        order_remaining: Micro,
    ) -> Candidate {
        let notional = (base_amount * price_quote) / MICRO;

        // Edge for a TAKER is directional, never the spread.
        //
        // The first version of this function credited a taker with a fraction of the
        // observed spread. That is backwards and it is the reason the agent held on
        // every live cycle: crossing the spread is a cost a taker pays, and the
        // spread is income for the maker who posted the order. A taker's only edge is
        // being right about direction. So: forecast the move, credit it when the side
        // agrees with the forecast, debit it when it does not, and charge the
        // half-spread crossing cost separately below.
        let expected_move = self.expected_move_bps(signals);
        let direction: i128 = match side {
            Side::Buy => 1,
            Side::Sell => -1,
        };
        let directional_edge = (notional * expected_move * direction) / 10_000;

        // Crossing cost: a taker gives up half the spread on entry.
        //
        // Clamped at zero because a CROSSED book (best bid above best ask) produces a
        // negative spread, and an unclamped negative cost is a credit that inflates
        // expected edge. The UI surfaced exactly this: a live book crossed at -1333 bps
        // was paying the agent to trade. A crossed book is a market structure anomaly,
        // never free money, so the cost floor is zero and the anomaly is disclosed in the
        // thesis text instead of being quietly monetised.
        let spread_bps = signals.spread_bps.as_ref().map_or(0, |e| e.value);
        let crossing_cost = (notional * spread_bps.max(0)) / (2 * 10_000);

        let expected_edge = directional_edge - crossing_cost;

        // Variance: proportional to realized volatility and notional.
        let vol_bps = signals.realized_vol_bps.as_ref().map_or(0, |e| e.value);
        let variance_penalty =
            (notional * vol_bps * i128::from(self.params.variance_weight_bps)) / (10_000 * 10_000);

        let capital_cost = (notional * i128::from(self.params.capital_cost_bps)) / 10_000;

        // Execution risk: taking a large fraction of a thin order is worse than
        // nibbling a thick one, and a one-sided book is worse than a two-sided one.
        let fraction_bps = if order_remaining > 0 {
            (base_amount * 10_000) / order_remaining
        } else {
            10_000
        };
        let thinness = if signals.live_order_count <= 2 { 2 } else { 1 };
        let execution_risk =
            (notional * fraction_bps * i128::from(self.params.thin_book_penalty_bps) * thinness)
                / (10_000 * 10_000);

        Candidate {
            action: Action::Take {
                order_id,
                side,
                base_amount,
                price_quote,
            },
            expected_edge_micro: expected_edge,
            variance_penalty_micro: variance_penalty,
            capital_cost_micro: capital_cost,
            execution_risk_penalty_micro: execution_risk,
            rejection_reason: None,
        }
    }

    /// Score, rank, and put the best candidate through the risk gate.
    ///
    /// Ranking then gating, in that order, and deliberately: the journal records
    /// what the engine WANTED alongside what risk allowed, which is the evidence
    /// that the gate is doing work rather than decorating a decision that was
    /// already safe.
    pub fn decide(
        &self,
        signals: &Signals,
        book: &[market_intel::OrderView],
        portfolio: &Portfolio,
        risk: &RiskEngine,
        ctx: &RiskContext,
        decision_id: u64,
    ) -> Decision {
        // BOUNDED BY THE MONEY THAT EXISTS. `free_margin_micro` is read from the token contract
        // under router execution, so this is the real spendable balance rather than an assumption.
        // Generating options the portfolio cannot pay for produced twenty-four refusals per cycle
        // and no trades: correct behaviour reached expensively, and indistinguishable from a
        // broken agent on screen.
        let mut candidates =
            self.generate_within(signals, book, Some(portfolio.free_margin_micro));

        // Put EVERY action candidate through the risk gate, not only the ones ranked
        // above the winner.
        //
        // The first version stopped at the first acceptable candidate, which meant a
        // high-scoring Hold short-circuited the loop and the journal recorded no
        // refusals at all. That made the risk gate invisible in exactly the case
        // where it was doing the most work. The gate is pure and cheap, so asking it
        // about everything costs nothing and the record then shows what the engine
        // wanted alongside what it was allowed.
        let mut refusals = 0usize;
        for c in &mut candidates {
            if let Some(intent) = c.action.to_intent(&self.market, self.kind, decision_id) {
                if let Err(r) = risk.evaluate(&intent, portfolio, ctx) {
                    c.rejection_reason = Some(format!("risk refused: {r:?}"));
                    refusals += 1;
                }
            }
        }

        // Rank by score, descending. Stable so equal scores keep generation order.
        let mut order: Vec<usize> = (0..candidates.len()).collect();
        order.sort_by(|a, b| {
            candidates[*b]
                .score_micro()
                .cmp(&candidates[*a].score_micro())
        });

        // A halt is disclosed, never silently reported as a preference to hold.
        // Holding while killed and holding because holding scored best are the same
        // action and completely different facts, and the journal must not conflate
        // them.
        if let Some(reason) = risk.kill_check(portfolio, ctx) {
            let hold_idx = candidates.iter().position(|c| c.action == Action::Hold);
            for (i, c) in candidates.iter_mut().enumerate() {
                if Some(i) != hold_idx && c.rejection_reason.is_none() {
                    c.rejection_reason = Some(format!("halted: {reason:?}"));
                }
            }
            return Decision {
                candidates,
                chosen_index: hold_idx,
                approved: None,
                risk_verdict: format!("halted: {reason:?}, {refusals} candidate(s) also refused"),
            };
        }

        let mut chosen_index = None;
        let mut approved = None;
        let mut verdict = format!("no candidate passed the risk gate, {refusals} refused");

        for idx in order {
            if candidates[idx].rejection_reason.is_some() {
                continue; // risk already refused this one
            }
            let action = candidates[idx].action.clone();
            match action.to_intent(&self.market, self.kind, decision_id) {
                None => {
                    chosen_index = Some(idx);
                    verdict = format!(
                        "hold outscored every permitted action, {refusals} candidate(s) refused by risk"
                    );
                    break;
                }
                Some(intent) => {
                    // Already known to pass, so this call produces the sealed token.
                    if let Ok(a) = risk.evaluate(&intent, portfolio, ctx) {
                        verdict = format!(
                            "approved{}, {refusals} candidate(s) refused by risk",
                            if a.requires_human_approval() {
                                ", human approval required"
                            } else {
                                ""
                            }
                        );
                        chosen_index = Some(idx);
                        approved = Some(a);
                        break;
                    }
                }
            }
        }

        // Distinguish "scored lower" from "risk refused" for everything left over.
        for (i, c) in candidates.iter_mut().enumerate() {
            if Some(i) != chosen_index && c.rejection_reason.is_none() {
                c.rejection_reason = Some("lower score".to_string());
            }
        }

        Decision {
            candidates,
            chosen_index,
            approved,
            risk_verdict: verdict,
        }
    }
}

/// The naive baseline for task 4.3. Fixed size, fixed behaviour, no signals.
///
/// A real runnable mode, not a straw man: it takes the best available order at a
/// fixed size whenever one exists. That is what a simple bot would actually do.
pub struct NaiveBaseline {
    pub fixed_base_amount: Micro,
    pub market: MarketId,
    pub kind: InstrumentKind,
}

impl NaiveBaseline {
    #[must_use]
    pub fn decide(
        &self,
        book: &[market_intel::OrderView],
        decision_id: u64,
    ) -> Option<OrderIntent> {
        let order = book.iter().find(|o| o.is_live())?;
        let amount = self.fixed_base_amount.min(order.remaining_base());
        if amount <= 0 {
            return None;
        }
        Some(OrderIntent {
            market: self.market.clone(),
            kind: self.kind,
            side: if order.maker_buys_base {
                Side::Sell
            } else {
                Side::Buy
            },
            size_micro: amount,
            limit_price_micro: order.price_quote,
            decision_id,
        })
    }
}

/// Guard used by the runtime and asserted in tests: a decision cycle that
/// evaluated exactly one candidate is not a search, and the runtime treats it as a
/// defect rather than shipping it as a decision.
pub fn assert_real_search(d: &Decision) -> Result<(), String> {
    match d.candidates.len() {
        0 => Err("no candidates generated".to_string()),
        1 => Err("exactly one candidate evaluated, this is not a search".to_string()),
        _ => Ok(()),
    }
}

#[must_use]
pub fn default_limits() -> Limits {
    Limits::conservative()
}

#[cfg(test)]
mod tests;
