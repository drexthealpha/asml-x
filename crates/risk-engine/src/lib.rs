//! The risk engine. Task 2.1.
//!
//! This crate is the only place in the system that can authorise an onchain
//! action. That is enforced by the type system rather than by discipline:
//! [`RiskApproved`] holds a private field, so no code outside this crate can
//! construct one, and the executor accepts nothing else. An agent that wants to
//! bypass the gate does not fail a runtime check, it fails to compile.
//!
//! Properties this module is built to make provable (Phase 3):
//! - No approval can exceed any configured limit.
//! - Once the kill switch is engaged, nothing is approved.
//! - The engine cannot be talked out of a refusal by retrying.
//! - Learning cannot widen a limit, because limits are an input the engine reads
//!   and never writes.
//!
//! Purity: no clock reads, no I/O, no interior mutability, no floats.

use core_types::{InstrumentKind, Micro, OrderIntent, Portfolio, TimestampMs, MICRO};

/// Hard limits. An input to the engine, never mutated by it. The learning agent
/// (Phase 7) is given no path to write this struct, which is what makes
/// "learning cannot widen a limit" a structural guarantee rather than a promise.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Limits {
    /// Maximum absolute exposure in any single market, micro quote units.
    pub max_market_notional_micro: Micro,
    /// Maximum gross exposure across the whole book.
    pub max_gross_notional_micro: Micro,
    /// Maximum absolute net directional exposure across the book.
    pub max_net_skew_micro: Micro,
    /// Maximum notional for one order.
    pub max_order_notional_micro: Micro,
    /// Minimum free margin that must remain after the order, micro quote units.
    pub min_free_margin_micro: Micro,
    /// Daily realized loss limit as a positive number. A realized PnL at or
    /// below its negation trips the kill switch.
    pub daily_loss_limit_micro: Micro,
    /// Maximum consecutive losing closes before halting.
    pub max_consecutive_losses: u32,
    /// Maximum age of any mark price used in a decision.
    pub max_mark_age_ms: u64,
    /// Maximum actions per minute, a crude but effective runaway guard.
    pub max_actions_per_minute: u32,
    /// Above this order notional, a human must approve.
    pub human_approval_threshold_micro: Micro,
    /// Cap on total RWA-linked exposure as a share of gross, in basis points.
    /// Phase 5 adds the oracle and redemption constraints on top.
    pub max_rwa_share_bps: u32,
    /// Absolute RWA allowance that applies regardless of share, micro quote units.
    ///
    /// Exists because a pure share cap is unsatisfiable at bootstrap: on an empty
    /// book the first RWA position is 100 percent of gross, so any share cap below
    /// 10000 bps refuses it forever. That is a cap that can never be satisfied rather
    /// than a cap that limits concentration. The rule is therefore: RWA exposure may
    /// reach the share of gross OR this absolute floor, whichever is larger.
    pub max_rwa_absolute_micro: Micro,
}

impl Limits {
    /// Deliberately small defaults. The demo runs real money on a real chain, so
    /// the safe direction is tiny.
    #[must_use]
    pub const fn conservative_testnet() -> Self {
        Self {
            max_market_notional_micro: 50 * MICRO,
            max_gross_notional_micro: 200 * MICRO,
            max_net_skew_micro: 75 * MICRO,
            max_order_notional_micro: 25 * MICRO,
            min_free_margin_micro: 5 * MICRO,
            daily_loss_limit_micro: 20 * MICRO,
            max_consecutive_losses: 4,
            max_mark_age_ms: 10_000,
            max_actions_per_minute: 30,
            human_approval_threshold_micro: 15 * MICRO,
            max_rwa_share_bps: 4_000,
            max_rwa_absolute_micro: 10 * MICRO,
        }
    }
}

/// Per-depositor limits, supplied by the user at deposit time and mirrored onchain in
/// `AgentVault.maxNotional`.
///
/// TWO INDEPENDENT ENFORCEMENTS, offchain and onchain, and neither is decorative. This struct is the
/// offchain half: it prevents the agent from even constructing an approved decision that exceeds a
/// user's limit. `AgentVault.openTrade` is the onchain half and re-checks the same bound, so a
/// compromised or replaced offchain binary still cannot exceed it. Task 8.3 demonstrates the onchain
/// revert with a real testnet transaction, because "enforced offchain and also onchain" is a claim
/// that has to be shown on chain to mean anything.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UserLimits {
    /// Maximum notional for one order placed with this user's funds, micro quote units.
    pub max_order_notional_micro: Micro,
    /// Maximum total exposure in one market for this user, micro quote units.
    pub max_market_notional_micro: Micro,
}

impl UserLimits {
    /// A user limit that constrains nothing, for callers with no per-user context.
    #[must_use]
    pub const fn unbounded() -> Self {
        Self {
            max_order_notional_micro: Micro::MAX,
            max_market_notional_micro: Micro::MAX,
        }
    }
}

impl Limits {
    /// Apply a user's limits by taking the MINIMUM of each bound.
    ///
    /// This is the whole safety argument, and it is one line long on purpose: `min` cannot widen.
    /// A user asking for a larger limit than the system allows gets the system's, silently and
    /// safely, and a user asking for a smaller one gets theirs. There is deliberately no branch
    /// here that could be written the other way round by a later edit without the proptest in
    /// tests.rs going red.
    #[must_use]
    pub fn tightened_by(&self, user: &UserLimits) -> Self {
        let mut out = self.clone();
        out.max_order_notional_micro = out
            .max_order_notional_micro
            .min(user.max_order_notional_micro);
        out.max_market_notional_micro = out
            .max_market_notional_micro
            .min(user.max_market_notional_micro);
        out
    }
}

/// Conditions that halt the agent. Independent of the per-order checks, because
/// a limit breach refuses one order while these stop everything.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KillReason {
    DailyLossBreached,
    ConsecutiveLossesBreached,
    MarketDataStale,
    OracleDivergence,
    RpcFailure,
    PositionReconciliationMismatch,
    LiquidationProximity,
    Manual,
}

/// RWA-specific live state, read from the vault each cycle.
///
/// Present only for RWA-linked markets. `None` means the market is not RWA-linked,
/// which is different from "RWA state unknown": an RWA market with unreadable state
/// must be treated as untradeable, and the runtime does that by refusing to build a
/// context at all rather than defaulting these fields.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RwaState {
    /// Age of the oracle mark in seconds.
    pub oracle_age_secs: u64,
    /// Issuer has halted the instrument.
    pub issuer_paused: bool,
    /// Seconds until the next redemption window opens. Zero while one is open.
    pub seconds_until_window: u64,
    /// Divergence between the oracle mark and the observed secondary price, bps.
    pub divergence_bps: u32,
    /// Yield index, micro-scaled. 1_000_000 is 1.0.
    pub yield_index_micro: Micro,
}

/// Policy thresholds for RWA-linked markets. Owner-set, never agent-set, mirroring
/// the onchain RwaRiskGuard so offchain and onchain agree on the same refusals.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RwaPolicy {
    pub max_oracle_age_secs: u64,
    pub window_buffer_secs: u64,
    pub max_divergence_bps: u32,
}

impl RwaPolicy {
    #[must_use]
    pub const fn conservative() -> Self {
        Self {
            max_oracle_age_secs: 3_600,
            window_buffer_secs: 43_200,
            max_divergence_bps: 300,
        }
    }
}

/// Live inputs that are not part of the book itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RiskContext {
    pub now_ms: TimestampMs,
    /// Actions already submitted in the trailing 60 seconds.
    pub actions_last_minute: u32,
    /// Set by the operator or by an external monitor. The agent has no writer.
    pub manual_kill: bool,
    /// True when the data pipeline has published DataStale.
    pub data_stale: bool,
    /// True when the executor found onchain state diverging from intent.
    pub reconciliation_mismatch: bool,
    /// True when the RPC layer is failing.
    pub rpc_failed: bool,
    /// RWA state, present only for RWA-linked markets.
    pub rwa: Option<RwaState>,
}

impl RiskContext {
    #[must_use]
    pub const fn healthy_at(now_ms: TimestampMs) -> Self {
        Self {
            now_ms,
            actions_last_minute: 0,
            manual_kill: false,
            data_stale: false,
            reconciliation_mismatch: false,
            rpc_failed: false,
            rwa: None,
        }
    }

    #[must_use]
    pub const fn with_rwa(mut self, rwa: RwaState) -> Self {
        self.rwa = Some(rwa);
        self
    }
}

/// Why an order was refused. Every variant carries the numbers, so the journal
/// and the UI can explain the refusal without re-deriving anything.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Refusal {
    Killed(KillReason),
    OrderNotionalTooLarge {
        got: Micro,
        limit: Micro,
    },
    MarketNotionalTooLarge {
        got: Micro,
        limit: Micro,
    },
    GrossNotionalTooLarge {
        got: Micro,
        limit: Micro,
    },
    NetSkewTooLarge {
        got: Micro,
        limit: Micro,
    },
    InsufficientFreeMargin {
        would_leave: Micro,
        minimum: Micro,
    },
    MarkPriceStale {
        age_ms: u64,
        max_age_ms: u64,
    },
    RateLimited {
        got: u32,
        limit: u32,
    },
    RwaShareTooLarge {
        got_bps: u32,
        limit_bps: u32,
    },
    /// A limit set by the DEPOSITOR whose funds would be used, not by the system. Kept distinct from
    /// `OrderNotionalTooLarge` so the refusal ledger can tell a user which of the two said no.
    UserLimitExceeded {
        got: Micro,
        limit: Micro,
    },
    NonPositiveSize,
    NonPositivePrice,
    // RWA-specific refusals. A generic bot has none of these, and each one is a real
    // failure mode of tokenized real-world assets.
    RwaOracleStale {
        age_secs: u64,
        max_secs: u64,
    },
    RwaIssuerPaused,
    RwaRedemptionWindowTooClose {
        until_secs: u64,
        buffer_secs: u64,
    },
    RwaOracleMarketDivergence {
        got_bps: u32,
        limit_bps: u32,
    },
    /// An RWA-linked market whose RWA state could not be read. Fails closed.
    RwaStateUnavailable,
}

impl Refusal {
    /// True when the refusal is RWA-specific, used by the UI and the side-by-side
    /// demo to prove the RWA path refuses for reasons the crypto path cannot.
    #[must_use]
    pub const fn is_rwa_specific(&self) -> bool {
        matches!(
            self,
            Refusal::RwaOracleStale { .. }
                | Refusal::RwaIssuerPaused
                | Refusal::RwaRedemptionWindowTooClose { .. }
                | Refusal::RwaOracleMarketDivergence { .. }
                | Refusal::RwaStateUnavailable
        )
    }
}

/// An order that has passed every check. The private unit field is the entire
/// mechanism: outside this crate there is no way to make one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RiskApproved<T> {
    inner: T,
    requires_human_approval: bool,
    approved_at_ms: TimestampMs,
    /// Not constructible externally. Do not remove.
    _seal: Seal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Seal;

impl<T> RiskApproved<T> {
    #[must_use]
    pub const fn get(&self) -> &T {
        &self.inner
    }

    #[must_use]
    pub fn into_inner(self) -> T {
        self.inner
    }

    #[must_use]
    pub const fn requires_human_approval(&self) -> bool {
        self.requires_human_approval
    }

    #[must_use]
    pub const fn approved_at_ms(&self) -> TimestampMs {
        self.approved_at_ms
    }
}

pub type Verdict = Result<RiskApproved<OrderIntent>, Refusal>;

/// The engine. Holds nothing mutable, so two calls with the same inputs always
/// give the same answer, and a retry cannot wear it down.
#[derive(Debug, Clone)]
pub struct RiskEngine {
    limits: Limits,
    rwa_policy: RwaPolicy,
}

impl RiskEngine {
    #[must_use]
    pub const fn new(limits: Limits) -> Self {
        Self {
            limits,
            rwa_policy: RwaPolicy::conservative(),
        }
    }

    #[must_use]
    pub const fn with_rwa_policy(mut self, policy: RwaPolicy) -> Self {
        self.rwa_policy = policy;
        self
    }

    #[must_use]
    pub const fn rwa_policy(&self) -> &RwaPolicy {
        &self.rwa_policy
    }

    /// RWA-specific refusals, checked before the generic caps so the reason names the
    /// actual cause. Mirrors RwaRiskGuard onchain, deliberately: two layers that
    /// disagree about what is tradeable would be worse than one.
    ///
    /// Applies ONLY to orders that increase exposure. `reduce_only` orders skip every
    /// check here, which is the same asymmetry the contract enforces: a stale oracle
    /// or a paused issuer is exactly when an agent most needs to exit.
    fn rwa_check(&self, intent: &OrderIntent, ctx: &RiskContext) -> Option<Refusal> {
        if intent.kind != InstrumentKind::RwaLinked {
            return None;
        }
        let Some(rwa) = ctx.rwa else {
            // An RWA market with unreadable state fails closed. Defaulting the fields
            // would let a missing read look like a healthy instrument.
            return Some(Refusal::RwaStateUnavailable);
        };
        let p = &self.rwa_policy;

        if rwa.issuer_paused {
            return Some(Refusal::RwaIssuerPaused);
        }
        if rwa.oracle_age_secs > p.max_oracle_age_secs {
            return Some(Refusal::RwaOracleStale {
                age_secs: rwa.oracle_age_secs,
                max_secs: p.max_oracle_age_secs,
            });
        }
        if rwa.seconds_until_window > 0 && rwa.seconds_until_window <= p.window_buffer_secs {
            return Some(Refusal::RwaRedemptionWindowTooClose {
                until_secs: rwa.seconds_until_window,
                buffer_secs: p.window_buffer_secs,
            });
        }
        if rwa.divergence_bps > p.max_divergence_bps {
            return Some(Refusal::RwaOracleMarketDivergence {
                got_bps: rwa.divergence_bps,
                limit_bps: p.max_divergence_bps,
            });
        }
        None
    }

    #[must_use]
    pub const fn limits(&self) -> &Limits {
        &self.limits
    }

    /// Kill switch evaluation, independent of any order.
    #[must_use]
    pub fn kill_check(&self, pf: &Portfolio, ctx: &RiskContext) -> Option<KillReason> {
        if ctx.manual_kill {
            return Some(KillReason::Manual);
        }
        if ctx.rpc_failed {
            return Some(KillReason::RpcFailure);
        }
        if ctx.reconciliation_mismatch {
            return Some(KillReason::PositionReconciliationMismatch);
        }
        if ctx.data_stale {
            return Some(KillReason::MarketDataStale);
        }
        if pf.realized_pnl_today_micro <= -self.limits.daily_loss_limit_micro {
            return Some(KillReason::DailyLossBreached);
        }
        if pf.consecutive_losses >= self.limits.max_consecutive_losses {
            return Some(KillReason::ConsecutiveLossesBreached);
        }
        None
    }

    /// The gate. This is the only constructor of `RiskApproved` in the system.
    ///
    /// Order of checks is deliberate: kill switch first, then cheap validity,
    /// then per-order size, then book-level aggregates. An order that fails
    /// several checks reports the most fundamental one, which is what an operator
    /// needs to see first.
    /// Evaluate an intent against a specific user's funds.
    ///
    /// The user's own bounds are checked FIRST, so the refusal names the user's limit rather than
    /// the system's. A ledger row reading "your 10 unit limit refused a 12 unit order" is actionable;
    /// one reading "the system limit of 25 refused a 12 unit order" would be actively confusing,
    /// because it names a limit the order did not breach.
    ///
    /// Then the ordinary `evaluate` runs with tightened limits. Every global check still applies,
    /// and `RiskApproved` still has exactly one constructor in the system.
    pub fn evaluate_for_user(
        &self,
        intent: &OrderIntent,
        pf: &Portfolio,
        ctx: &RiskContext,
        user: &UserLimits,
    ) -> Verdict {
        let order_notional = intent.notional_micro();
        if order_notional > user.max_order_notional_micro {
            return Err(Refusal::UserLimitExceeded {
                got: order_notional,
                limit: user.max_order_notional_micro,
            });
        }

        let projected_market =
            (pf.exposure_in_market_micro(&intent.market) + intent.signed_notional_micro()).abs();
        if projected_market > user.max_market_notional_micro {
            return Err(Refusal::UserLimitExceeded {
                got: projected_market,
                limit: user.max_market_notional_micro,
            });
        }

        let tightened = Self {
            limits: self.limits.tightened_by(user),
            rwa_policy: self.rwa_policy,
        };
        tightened.evaluate(intent, pf, ctx)
    }

    pub fn evaluate(&self, intent: &OrderIntent, pf: &Portfolio, ctx: &RiskContext) -> Verdict {
        if let Some(reason) = self.kill_check(pf, ctx) {
            return Err(Refusal::Killed(reason));
        }

        if intent.size_micro <= 0 {
            return Err(Refusal::NonPositiveSize);
        }
        if intent.limit_price_micro <= 0 {
            return Err(Refusal::NonPositivePrice);
        }

        // Does this order move exposure toward zero for its market?
        //
        // Derived from state rather than taken as a flag on the intent. A
        // `reduce_only` boolean supplied by the caller is something an agent could set
        // wrongly, by mistake or otherwise, to slip past the RWA refusals. The signs
        // of current exposure and the new order cannot lie.
        let current_market_exposure = pf.exposure_in_market_micro(&intent.market);
        let is_reducing = current_market_exposure != 0
            && current_market_exposure.signum() != intent.signed_notional_micro().signum();

        // RWA refusals apply only to orders that ADD exposure. Exits are never
        // blocked, matching RwaRiskGuard onchain.
        if !is_reducing {
            if let Some(r) = self.rwa_check(intent, ctx) {
                return Err(r);
            }
        }

        if ctx.actions_last_minute >= self.limits.max_actions_per_minute {
            return Err(Refusal::RateLimited {
                got: ctx.actions_last_minute,
                limit: self.limits.max_actions_per_minute,
            });
        }

        // Any mark price we would rely on must be fresh. An empty book has no
        // marks, which is fresh by vacuity and correct: opening the first
        // position cannot depend on a mark that does not exist.
        if let Some(age) = pf.worst_mark_age_ms(ctx.now_ms) {
            if age > self.limits.max_mark_age_ms {
                return Err(Refusal::MarkPriceStale {
                    age_ms: age,
                    max_age_ms: self.limits.max_mark_age_ms,
                });
            }
        }

        let order_notional = intent.notional_micro();
        if order_notional > self.limits.max_order_notional_micro {
            return Err(Refusal::OrderNotionalTooLarge {
                got: order_notional,
                limit: self.limits.max_order_notional_micro,
            });
        }

        // Post-trade projections. The check is on where the book WOULD be, never
        // on where it is now, which is the bug that lets a book creep past a
        // limit one order at a time.
        let signed = intent.signed_notional_micro();

        let projected_market = (pf.exposure_in_market_micro(&intent.market) + signed).abs();
        if projected_market > self.limits.max_market_notional_micro {
            return Err(Refusal::MarketNotionalTooLarge {
                got: projected_market,
                limit: self.limits.max_market_notional_micro,
            });
        }

        // Gross is bounded above by current gross plus this order's notional.
        // Using the bound rather than a per-position recomputation is
        // deliberately conservative: it can refuse an order that would actually
        // have reduced gross exposure. Refusing a safe order is acceptable;
        // allowing an unsafe one is not.
        let projected_gross = pf.gross_exposure_micro() + order_notional;
        if projected_gross > self.limits.max_gross_notional_micro {
            return Err(Refusal::GrossNotionalTooLarge {
                got: projected_gross,
                limit: self.limits.max_gross_notional_micro,
            });
        }

        let projected_net = (pf.net_exposure_micro() + signed).abs();
        if projected_net > self.limits.max_net_skew_micro {
            return Err(Refusal::NetSkewTooLarge {
                got: projected_net,
                limit: self.limits.max_net_skew_micro,
            });
        }

        let would_leave = pf.free_margin_micro - order_notional;
        if would_leave < self.limits.min_free_margin_micro {
            return Err(Refusal::InsufficientFreeMargin {
                would_leave,
                minimum: self.limits.min_free_margin_micro,
            });
        }

        // RWA share cap. Phase 5 layers oracle age, redemption windows, and
        // issuer pause flags on top of this.
        // Concentration cap on RWA exposure. Skipped when reducing, for the same
        // reason every other RWA check is: an exit must never be blocked, and a
        // concentration limit that traps a position converts a risk control into the
        // risk.
        if intent.kind == InstrumentKind::RwaLinked && !is_reducing {
            let projected_rwa =
                pf.exposure_of_kind_micro(InstrumentKind::RwaLinked) + order_notional;
            let share_allowance =
                (projected_gross * i128::from(self.limits.max_rwa_share_bps)) / 10_000;
            let allowance = share_allowance.max(self.limits.max_rwa_absolute_micro);
            if projected_rwa > allowance {
                // Report the share so the number in the refusal is the meaningful one.
                //
                // This was `if projected_gross > 0 { .. } else { 10_000 }`. cargo-mutants showed
                // that `> 0` and `>= 0` are indistinguishable here, and that is not a missing
                // test: `projected_gross` is `gross_exposure_micro() + order_notional`, gross is
                // non-negative by construction, and a zero or negative order size is already
                // refused earlier in this function. So the divisor is always at least
                // `order_notional`, which is strictly positive, and the else branch was
                // unreachable. Deleting dead code is the right fix for an equivalent mutant;
                // adding a test for a branch that cannot execute is not.
                let share_bps =
                    u32::try_from((projected_rwa * 10_000) / projected_gross).unwrap_or(u32::MAX);
                return Err(Refusal::RwaShareTooLarge {
                    got_bps: share_bps,
                    limit_bps: self.limits.max_rwa_share_bps,
                });
            }
        }

        Ok(RiskApproved {
            inner: intent.clone(),
            requires_human_approval: order_notional > self.limits.human_approval_threshold_micro,
            approved_at_ms: ctx.now_ms,
            _seal: Seal,
        })
    }

    /// Convenience for the market-neutral question "may we act at all right now".
    #[must_use]
    pub fn is_halted(&self, pf: &Portfolio, ctx: &RiskContext) -> bool {
        self.kill_check(pf, ctx).is_some()
    }
}

#[cfg(test)]
mod tests;
