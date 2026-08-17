//! The Learning Agent. Phase 7.
//!
//! What this does: attaches realized outcomes to decisions, attributes them to the
//! signal and parameter set that produced them, and updates parameters from measured
//! accuracy. Learned state persists across restarts.
//!
//! What it structurally CANNOT do, and why that is the important part:
//!
//! `Learner` has no field, argument, or return type anywhere in its API that mentions
//! `risk_engine::Limits`. It produces `decision_engine::Params` and nothing else. So
//! "learning cannot widen a risk limit" is not a policy someone must remember, it is a
//! statement about which types exist. The test
//! `learning_cannot_reach_a_risk_limit_because_it_has_no_type_for_one` pins that, and
//! the mutation gate confirms the pin can fail.
//!
//! Honesty constraints baked in:
//! - Every parameter change records the trigger, the sample size, and the measured
//!   accuracy that caused it. A change with no attribution is refused.
//! - Updates are bounded on both sides. An unbounded learner is a random walk with a
//!   good story.
//! - `MIN_SAMPLES_TO_UPDATE` blocks learning from noise. Adjusting a weight on three
//!   observations is not learning, it is overfitting with extra steps.

use core_types::{Micro, TimestampMs, MICRO};
use decision_engine::Params;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Below this many settled outcomes for a signal, no parameter moves. Small enough to
/// show movement in a demo, large enough that a single lucky trade cannot swing it.
pub const MIN_SAMPLES_TO_UPDATE: u32 = 5;

/// Moves smaller than this are UNSCORED, not wrong.
///
/// Found by the first live run: the hit rate came back as exactly 0 out of 14, which is
/// not a bad signal, it is a broken scorer. On a nearly static book the realized move is
/// zero, and `realized > 0` is false for a zero move, so every single forecast was
/// counted as incorrect and every signal decayed to no weight regardless of quality.
///
/// A market that did not move tells you nothing about whether a directional call was
/// right. Those samples are now dropped rather than counted against the signal.
pub const DEAD_BAND_BPS: i128 = 5;

/// Hard bounds on every learnable parameter. Learning may move within these and never
/// outside them, which is what stops a feedback loop from walking a parameter to
/// absurdity.
pub const MOMENTUM_WEIGHT_MIN: u32 = 0;
pub const MOMENTUM_WEIGHT_MAX: u32 = 6_000;
pub const THIN_BOOK_PENALTY_MIN: u32 = 25;
pub const THIN_BOOK_PENALTY_MAX: u32 = 2_000;

/// Which direction the decision expected the mid to move.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Predicted {
    Up,
    Down,
    /// The decision was a hold, so there is nothing to be right or wrong about.
    NoView,
}

/// A decision awaiting its outcome.
#[derive(Debug, Clone)]
pub struct Pending {
    pub decision_id: u64,
    pub predicted: Predicted,
    pub mid_at_decision: Micro,
    pub expected_edge_micro: Micro,
    pub opened_at_ms: TimestampMs,
    /// The parameter set in force when this decision was made, so the outcome is
    /// attributed to the parameters that actually produced it rather than to whatever
    /// is current when it settles.
    pub params_at_decision: Params,
    pub signal_name: String,
    /// Size of the position taken, in micro base units. Zero for a hold.
    ///
    /// TASK 14.4. Without this the learner can score a DIRECTION but cannot produce a realized PnL,
    /// because a move in basis points says nothing about money until it is multiplied by a size. A
    /// system that reports hit rate and calls it a result is grading its forecasts, not its trading:
    /// a signal can be right most of the time and lose, by being right small and wrong large.
    pub size_micro: Micro,
}

/// A settled outcome.
#[derive(Debug, Clone)]
pub struct Outcome {
    pub decision_id: u64,
    pub signal_name: String,
    pub predicted: Predicted,
    pub mid_at_decision: Micro,
    pub mid_at_settle: Micro,
    /// Realized move in basis points, signed.
    pub realized_move_bps: i128,
    /// True when the predicted direction matched the realized move.
    pub direction_correct: bool,
    /// Realized minus expected, in micro quote units. Negative means the decision
    /// overestimated its own edge.
    pub edge_error_micro: Micro,
    pub settled_at_ms: TimestampMs,
    /// Size the decision took, in micro base units, carried through from `Pending`.
    pub size_micro: Micro,
    /// The edge the decision expected, carried through so a consumer never has to reconstruct it
    /// from `edge_error_micro`. Reconstructing it requires re-applying the direction sign and gets
    /// the answer wrong for a short, which is precisely the kind of quietly-derived number this
    /// project treats as a defect.
    pub expected_edge_micro: Micro,
    /// TASK 14.4. Realized PnL in micro QUOTE units, signed.
    ///
    /// `size * (mid_at_settle - mid_at_decision)` for a long, negated for a short, divided by the
    /// micro scale once because both factors are micro-scaled.
    ///
    /// MARK TO MARKET, NOT CASH. This is the position's value change against a later observed mid,
    /// not proceeds from a closing trade, and the evidence says so in those words. Calling it
    /// realized cash would be claiming a round trip that did not happen.
    pub realized_pnl_micro: Micro,
}

/// Per-signal accuracy tally.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SignalStats {
    pub samples: u32,
    pub correct: u32,
    /// Sum of signed realized moves, for detecting a biased signal.
    pub sum_realized_bps: i128,
    /// Sum of (realized minus expected), for detecting systematic over-optimism.
    pub sum_edge_error_micro: Micro,
}

impl SignalStats {
    /// Hit rate in basis points. 5000 is a coin flip.
    #[must_use]
    pub fn hit_rate_bps(&self) -> u32 {
        if self.samples == 0 {
            return 0;
        }
        u32::try_from((u64::from(self.correct) * 10_000) / u64::from(self.samples)).unwrap_or(0)
    }

    #[must_use]
    pub fn mean_edge_error_micro(&self) -> Micro {
        if self.samples == 0 {
            return 0;
        }
        self.sum_edge_error_micro / i128::from(self.samples)
    }
}

/// One recorded parameter change, with the evidence that caused it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParamChange {
    pub at_ms: TimestampMs,
    pub parameter: String,
    pub from: u32,
    pub to: u32,
    pub trigger: String,
    pub samples: u32,
    pub hit_rate_bps: u32,
}

/// The learner. Note the absence of any `Limits` in this type or its methods.
pub struct Learner {
    params: Params,
    stats: HashMap<String, SignalStats>,
    pending: Vec<Pending>,
    history: Vec<ParamChange>,
    path: Option<PathBuf>,
    settled_count: u64,
    /// Decisions dropped because the market did not move enough to judge them.
    /// Surfaced so a flat market is visible as "no information" rather than hidden.
    unscored_flat: u64,
}

impl Learner {
    #[must_use]
    pub fn new(params: Params) -> Self {
        Self {
            params,
            stats: HashMap::new(),
            pending: Vec::new(),
            history: Vec::new(),
            path: None,
            settled_count: 0,
            unscored_flat: 0,
        }
    }

    /// Decisions dropped because the market was flat. A high number here relative to
    /// `settled_count` means the venue is too quiet to learn from, which is information
    /// worth showing rather than burying.
    #[must_use]
    pub const fn unscored_flat(&self) -> u64 {
        self.unscored_flat
    }

    /// Load persisted state, or start cold if the file is absent.
    ///
    /// Persistence matters for an honest claim: if learned state vanished on restart,
    /// any demonstration of improvement would be an artifact of one process lifetime.
    pub fn load(path: impl AsRef<Path>, default_params: Params) -> Self {
        let path = path.as_ref().to_path_buf();
        let mut me = Self::new(default_params);
        me.path = Some(path.clone());
        if let Ok(text) = std::fs::read_to_string(&path) {
            if let Ok(v) = serde_json::from_str::<Value>(&text) {
                if let Some(p) = v.get("params") {
                    me.params = Params {
                        momentum_weight_bps: u32::try_from(
                            p.get("momentum_weight_bps")
                                .and_then(Value::as_u64)
                                .unwrap_or(u64::from(me.params.momentum_weight_bps)),
                        )
                        .unwrap_or(me.params.momentum_weight_bps),
                        variance_weight_bps: u32::try_from(
                            p.get("variance_weight_bps")
                                .and_then(Value::as_u64)
                                .unwrap_or(u64::from(me.params.variance_weight_bps)),
                        )
                        .unwrap_or(me.params.variance_weight_bps),
                        capital_cost_bps: me.params.capital_cost_bps,
                        thin_book_penalty_bps: u32::try_from(
                            p.get("thin_book_penalty_bps")
                                .and_then(Value::as_u64)
                                .unwrap_or(u64::from(me.params.thin_book_penalty_bps)),
                        )
                        .unwrap_or(me.params.thin_book_penalty_bps),
                        min_confidence_bps: me.params.min_confidence_bps,
                        max_take_fraction_bps: me.params.max_take_fraction_bps,
                    };
                }
                if let Some(stats) = v.get("stats").and_then(Value::as_object) {
                    for (name, s) in stats {
                        me.stats.insert(
                            name.clone(),
                            SignalStats {
                                samples: u32::try_from(
                                    s.get("samples").and_then(Value::as_u64).unwrap_or(0),
                                )
                                .unwrap_or(0),
                                correct: u32::try_from(
                                    s.get("correct").and_then(Value::as_u64).unwrap_or(0),
                                )
                                .unwrap_or(0),
                                sum_realized_bps: s
                                    .get("sum_realized_bps")
                                    .and_then(Value::as_str)
                                    .and_then(|x| x.parse().ok())
                                    .unwrap_or(0),
                                sum_edge_error_micro: s
                                    .get("sum_edge_error_micro")
                                    .and_then(Value::as_str)
                                    .and_then(|x| x.parse().ok())
                                    .unwrap_or(0),
                            },
                        );
                    }
                }
                // HISTORY MUST BE RESTORED, and it was not. `save` wrote every parameter change and
                // `load` silently dropped them, so the recorded history was only ever the CURRENT
                // process's changes. Task 14.6 surfaced it: the panel showed momentum weight moving
                // 411 -> 401 when it had actually fallen from its default of 2000, understating the
                // learning effect by two orders of magnitude while looking perfectly plausible.
                //
                // Same defect shape as the pending queue, which was fixed for the same reason: a
                // sequence of short runs learned nothing and reported `settled 0` while appearing to
                // work. Anything written on save and not read on load is a lie the next run tells.
                if let Some(hist) = v.get("history").and_then(Value::as_array) {
                    for h in hist {
                        let u = |k: &str| -> u32 {
                            u32::try_from(h.get(k).and_then(Value::as_u64).unwrap_or(0))
                                .unwrap_or(0)
                        };
                        me.history.push(ParamChange {
                            at_ms: h.get("at_ms").and_then(Value::as_u64).unwrap_or(0),
                            parameter: h
                                .get("parameter")
                                .and_then(Value::as_str)
                                .unwrap_or("")
                                .to_string(),
                            from: u("from"),
                            to: u("to"),
                            trigger: h
                                .get("trigger")
                                .and_then(Value::as_str)
                                .unwrap_or("")
                                .to_string(),
                            samples: u("samples"),
                            hit_rate_bps: u("hit_rate_bps"),
                        });
                    }
                }

                me.settled_count = v.get("settled_count").and_then(Value::as_u64).unwrap_or(0);
                me.unscored_flat = v.get("unscored_flat").and_then(Value::as_u64).unwrap_or(0);

                if let Some(pend) = v.get("pending").and_then(Value::as_array) {
                    for p in pend {
                        let predicted = match p.get("predicted").and_then(Value::as_str) {
                            Some("up") => Predicted::Up,
                            Some("down") => Predicted::Down,
                            _ => Predicted::NoView,
                        };
                        me.pending.push(Pending {
                            decision_id: p.get("decision_id").and_then(Value::as_u64).unwrap_or(0),
                            predicted,
                            mid_at_decision: p
                                .get("mid_at_decision")
                                .and_then(Value::as_str)
                                .and_then(|x| x.parse().ok())
                                .unwrap_or(0),
                            expected_edge_micro: p
                                .get("expected_edge_micro")
                                .and_then(Value::as_str)
                                .and_then(|x| x.parse().ok())
                                .unwrap_or(0),
                            opened_at_ms: p
                                .get("opened_at_ms")
                                .and_then(Value::as_u64)
                                .unwrap_or(0),
                            params_at_decision: me.params.clone(),
                            signal_name: p
                                .get("signal_name")
                                .and_then(Value::as_str)
                                .unwrap_or("imbalance_bps")
                                .to_string(),
                            // Absent in state files written before 14.4. Defaulting to zero makes
                            // such a forecast settle with a realized PnL of exactly zero, which is
                            // the honest reading: the size was never recorded, so no PnL can be
                            // claimed for it. It is NOT dropped, because its direction is still
                            // scoreable and discarding it would quietly shrink the sample.
                            size_micro: p
                                .get("size_micro")
                                .and_then(Value::as_str)
                                .and_then(|x| x.parse().ok())
                                .unwrap_or(0),
                        });
                    }
                }
            }
        }
        me
    }

    pub fn save(&self) -> std::io::Result<()> {
        let Some(path) = &self.path else {
            return Ok(());
        };
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let stats: serde_json::Map<String, Value> = self
            .stats
            .iter()
            .map(|(k, s)| {
                (
                    k.clone(),
                    json!({
                        "samples": s.samples,
                        "correct": s.correct,
                        "hit_rate_bps": s.hit_rate_bps(),
                        "sum_realized_bps": s.sum_realized_bps.to_string(),
                        "sum_edge_error_micro": s.sum_edge_error_micro.to_string(),
                    }),
                )
            })
            .collect();
        // Pending decisions MUST persist. Without this, every process exit silently
        // discarded outstanding forecasts, so a sequence of short runs learned nothing
        // and reported `settled 0` while looking like it was working. A forecast that
        // cannot outlive the process can never be scored against a later price.
        let pending: Vec<Value> = self
            .pending
            .iter()
            .map(|p| {
                json!({
                    "decision_id": p.decision_id,
                    "predicted": match p.predicted {
                        Predicted::Up => "up",
                        Predicted::Down => "down",
                        Predicted::NoView => "noview",
                    },
                    "mid_at_decision": p.mid_at_decision.to_string(),
                    "expected_edge_micro": p.expected_edge_micro.to_string(),
                    "opened_at_ms": p.opened_at_ms,
                    "signal_name": p.signal_name,
                    "size_micro": p.size_micro.to_string(),
                })
            })
            .collect();

        let v = json!({
            "pending": pending,
            "unscored_flat": self.unscored_flat,
            "params": {
                "momentum_weight_bps": self.params.momentum_weight_bps,
                "variance_weight_bps": self.params.variance_weight_bps,
                "thin_book_penalty_bps": self.params.thin_book_penalty_bps,
            },
            "stats": stats,
            "settled_count": self.settled_count,
            "history": self.history.iter().map(|c| json!({
                "at_ms": c.at_ms,
                "parameter": c.parameter,
                "from": c.from,
                "to": c.to,
                "trigger": c.trigger,
                "samples": c.samples,
                "hit_rate_bps": c.hit_rate_bps,
            })).collect::<Vec<_>>(),
        });
        std::fs::write(path, serde_json::to_string_pretty(&v)?)
    }

    #[must_use]
    pub const fn params(&self) -> &Params {
        &self.params
    }

    #[must_use]
    pub fn stats_for(&self, signal: &str) -> SignalStats {
        self.stats.get(signal).cloned().unwrap_or_default()
    }

    #[must_use]
    pub fn history(&self) -> &[ParamChange] {
        &self.history
    }

    #[must_use]
    pub const fn settled_count(&self) -> u64 {
        self.settled_count
    }

    #[must_use]
    pub fn pending_count(&self) -> usize {
        self.pending.len()
    }

    pub fn record_decision(&mut self, p: Pending) {
        self.pending.push(p);
    }

    /// Settle every pending decision at least `lag_ms` old against the current mid.
    ///
    /// A lag is required rather than settling immediately: a directional forecast that
    /// is scored against the price it was made at is scored against itself, and would
    /// report a perfect hit rate for a signal with no information at all.
    pub fn settle_due(
        &mut self,
        now_ms: TimestampMs,
        current_mid: Micro,
        lag_ms: u64,
    ) -> Vec<Outcome> {
        let mut settled = Vec::new();
        let mut still_pending = Vec::new();

        for p in std::mem::take(&mut self.pending) {
            if now_ms.saturating_sub(p.opened_at_ms) < lag_ms || p.predicted == Predicted::NoView {
                // Holds are dropped rather than kept forever: there is no direction to
                // score, so retaining them would grow the queue without adding signal.
                if p.predicted != Predicted::NoView {
                    still_pending.push(p);
                }
                continue;
            }
            if p.mid_at_decision <= 0 || current_mid <= 0 {
                continue;
            }

            let realized_move_bps =
                ((current_mid - p.mid_at_decision) * 10_000) / p.mid_at_decision;

            // A market that did not move cannot judge a directional call. Drop the
            // sample instead of scoring it as wrong. See DEAD_BAND_BPS.
            if realized_move_bps.abs() < DEAD_BAND_BPS {
                self.unscored_flat += 1;
                continue;
            }

            let direction_correct = match p.predicted {
                Predicted::Up => realized_move_bps > 0,
                Predicted::Down => realized_move_bps < 0,
                Predicted::NoView => false,
            };
            // Realized edge approximated as the favourable move, so an unfavourable move
            // produces a negative realized edge and a negative error.
            let realized_edge = match p.predicted {
                Predicted::Up => realized_move_bps,
                Predicted::Down => -realized_move_bps,
                Predicted::NoView => 0,
            };
            let edge_error_micro = realized_edge - p.expected_edge_micro;

            // TASK 14.4. Realized PnL in micro quote units. Integer arithmetic throughout, as the
            // workspace lint denies floats in this crate: the division by MICRO happens once,
            // because size and the price delta are each micro-scaled and their product is
            // micro-squared. Truncation toward zero is acceptable and deliberate, since a rounding
            // that could round a loss up to zero is the one that would flatter the result.
            let price_delta = current_mid - p.mid_at_decision;
            let directional = match p.predicted {
                Predicted::Up => price_delta,
                Predicted::Down => -price_delta,
                Predicted::NoView => 0,
            };
            let realized_pnl_micro = (p.size_micro * directional) / MICRO;

            let s = self.stats.entry(p.signal_name.clone()).or_default();
            s.samples += 1;
            if direction_correct {
                s.correct += 1;
            }
            s.sum_realized_bps += realized_move_bps;
            s.sum_edge_error_micro += edge_error_micro;

            self.settled_count += 1;
            settled.push(Outcome {
                decision_id: p.decision_id,
                signal_name: p.signal_name,
                predicted: p.predicted,
                mid_at_decision: p.mid_at_decision,
                mid_at_settle: current_mid,
                realized_move_bps,
                direction_correct,
                edge_error_micro,
                settled_at_ms: now_ms,
                size_micro: p.size_micro,
                expected_edge_micro: p.expected_edge_micro,
                realized_pnl_micro,
            });
        }

        self.pending = still_pending;
        settled
    }

    /// Update parameters from measured accuracy. Returns the changes made.
    ///
    /// The update rule, stated so it can be argued with:
    /// - The imbalance signal's hit rate drives `momentum_weight_bps`. A hit rate above
    ///   a coin flip raises the weight, below lowers it, proportional to the distance
    ///   from 5000 bps. A signal that is right half the time carries no information and
    ///   converges toward zero weight.
    /// - Systematic over-optimism (negative mean edge error) raises
    ///   `thin_book_penalty_bps`, because consistently realizing less than expected is
    ///   what adverse selection looks like from the inside.
    ///
    /// Both moves are clamped, and nothing moves below `MIN_SAMPLES_TO_UPDATE`.
    pub fn update_params(&mut self, now_ms: TimestampMs) -> Vec<ParamChange> {
        let mut changes = Vec::new();
        let stats = self.stats_for("imbalance_bps");

        if stats.samples < MIN_SAMPLES_TO_UPDATE {
            return changes;
        }

        // ---- momentum weight from hit rate ----
        let hit = i64::from(stats.hit_rate_bps());
        let edge_from_coinflip = hit - 5_000; // positive means better than chance
        let old = self.params.momentum_weight_bps;
        // Move a tenth of the distance from a coin flip, so a strong signal earns weight
        // over several updates instead of jumping on one batch.
        let delta = (edge_from_coinflip * i64::from(old.max(500))) / 50_000;
        let proposed = i64::from(old) + delta;
        let new = proposed.clamp(
            i64::from(MOMENTUM_WEIGHT_MIN),
            i64::from(MOMENTUM_WEIGHT_MAX),
        );
        let new = u32::try_from(new).unwrap_or(old);
        if new != old {
            self.params.momentum_weight_bps = new;
            changes.push(ParamChange {
                at_ms: now_ms,
                parameter: "momentum_weight_bps".to_string(),
                from: old,
                to: new,
                trigger: format!(
                    "imbalance_bps hit rate {} bps over {} settled outcomes, {} a coin flip",
                    stats.hit_rate_bps(),
                    stats.samples,
                    if edge_from_coinflip >= 0 {
                        "above"
                    } else {
                        "below"
                    }
                ),
                samples: stats.samples,
                hit_rate_bps: stats.hit_rate_bps(),
            });
        }

        // ---- thin book penalty from systematic over-optimism ----
        let mean_err = stats.mean_edge_error_micro();
        let old_pen = self.params.thin_book_penalty_bps;
        let pen_delta: i64 = if mean_err < 0 { 25 } else { -10 };
        let new_pen = (i64::from(old_pen) + pen_delta).clamp(
            i64::from(THIN_BOOK_PENALTY_MIN),
            i64::from(THIN_BOOK_PENALTY_MAX),
        );
        let new_pen = u32::try_from(new_pen).unwrap_or(old_pen);
        if new_pen != old_pen {
            self.params.thin_book_penalty_bps = new_pen;
            changes.push(ParamChange {
                at_ms: now_ms,
                parameter: "thin_book_penalty_bps".to_string(),
                from: old_pen,
                to: new_pen,
                trigger: format!(
                    "mean edge error {} micro over {} outcomes, decisions {} their own edge",
                    mean_err,
                    stats.samples,
                    if mean_err < 0 {
                        "overestimated"
                    } else {
                        "did not overestimate"
                    }
                ),
                samples: stats.samples,
                hit_rate_bps: stats.hit_rate_bps(),
            });
        }

        self.history.extend(changes.iter().cloned());
        changes
    }

    /// Human-readable summary for the UI and the demo.
    #[must_use]
    pub fn explain(&self) -> String {
        if self.history.is_empty() {
            return format!(
                "no parameter changes yet: {} settled outcomes, {} needed before any move",
                self.settled_count, MIN_SAMPLES_TO_UPDATE
            );
        }
        let last = &self.history[self.history.len() - 1];
        format!(
            "after {} settled outcomes I changed {} from {} to {} because {}",
            last.samples, last.parameter, last.from, last.to, last.trigger
        )
    }
}

#[cfg(test)]
mod tests;
