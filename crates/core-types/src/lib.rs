//! Shared value types for ASML-X.
//!
//! Two deliberate constraints, both there to make the risk engine formally
//! verifiable later (Phase 3):
//!
//! 1. No floating point anywhere. All money and prices are integers in fixed
//!    micro-units (1e6). Float arithmetic is denied at the lint level in the
//!    workspace manifest. Floats make invariants unprovable and introduce
//!    rounding an adversary can steer.
//! 2. No clock reads. Every function that needs the time takes it as an
//!    argument. A pure function of its inputs can be exhaustively tested and
//!    symbolically executed. One that reads a clock cannot.

/// Micro-units per whole unit. All notionals and prices use this scale.
pub const MICRO: i128 = 1_000_000;

/// Milliseconds since Unix epoch. Passed in, never read from a clock.
pub type TimestampMs = u64;

/// A signed quantity in micro-units.
pub type Micro = i128;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Side {
    Buy,
    Sell,
}

impl Side {
    #[must_use]
    pub const fn sign(self) -> i128 {
        match self {
            Side::Buy => 1,
            Side::Sell => -1,
        }
    }
}

/// Which kind of instrument, because the risk rules genuinely differ.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum InstrumentKind {
    Spot,
    Perp,
    /// Binary or categorical outcome market.
    Outcome,
    /// RWA-linked instrument. Carries oracle and redemption risk that the
    /// generic paths do not model. See Phase 5.
    RwaLinked,
}

/// Provenance of an instrument, surfaced in the UI so nothing can pass a
/// self-deployed stand-in off as a live third-party venue.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Provenance {
    ThirdPartyLive,
    SelfDeployedStandIn,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct MarketId(pub String);

impl MarketId {
    pub fn new(s: impl Into<String>) -> Self {
        Self(s.into())
    }
}

/// A value that knows how old it is. A price without an age is a bug, so the
/// type system refuses to hand one over without a timestamp.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Stamped<T> {
    pub value: T,
    pub observed_at_ms: TimestampMs,
}

impl<T> Stamped<T> {
    pub const fn new(value: T, observed_at_ms: TimestampMs) -> Self {
        Self {
            value,
            observed_at_ms,
        }
    }

    /// Age at `now_ms`. Saturating, so a clock that went backwards reports 0
    /// rather than panicking or wrapping to a huge number that would look fresh.
    #[must_use]
    pub const fn age_ms(&self, now_ms: TimestampMs) -> u64 {
        now_ms.saturating_sub(self.observed_at_ms)
    }

    #[must_use]
    pub const fn is_stale(&self, now_ms: TimestampMs, max_age_ms: u64) -> bool {
        self.age_ms(now_ms) > max_age_ms
    }
}

/// What the agent wants to do, before any risk check has seen it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrderIntent {
    pub market: MarketId,
    pub kind: InstrumentKind,
    pub side: Side,
    /// Size in micro base units. Always positive; direction lives in `side`.
    pub size_micro: Micro,
    /// Limit price in micro quote units per whole base unit.
    pub limit_price_micro: Micro,
    /// Which journal entry produced this intent, so every onchain action traces
    /// back to the reasoning that caused it.
    pub decision_id: u64,
}

impl OrderIntent {
    /// Notional in micro quote units.
    ///
    /// Both inputs are micro-scaled, so the product is micro-squared and must be
    /// divided back down once. Getting this wrong by a factor of 1e6 is the
    /// classic fixed-point bug, so it lives in exactly one place.
    #[must_use]
    pub const fn notional_micro(&self) -> Micro {
        (self.size_micro * self.limit_price_micro) / MICRO
    }

    /// Signed notional: positive for buys, negative for sells.
    #[must_use]
    pub const fn signed_notional_micro(&self) -> Micro {
        self.notional_micro() * self.side.sign()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Position {
    pub market: MarketId,
    pub kind: InstrumentKind,
    /// Signed size in micro base units. Positive is long.
    pub net_size_micro: Micro,
    /// Mark price used for exposure, with its age.
    pub mark_price_micro: Stamped<Micro>,
}

impl Position {
    /// Signed exposure in micro quote units.
    #[must_use]
    pub const fn signed_exposure_micro(&self) -> Micro {
        (self.net_size_micro * self.mark_price_micro.value) / MICRO
    }

    #[must_use]
    pub const fn abs_exposure_micro(&self) -> Micro {
        self.signed_exposure_micro().abs()
    }
}

/// Everything the risk engine needs to know about our own book.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Portfolio {
    pub positions: Vec<Position>,
    /// Free collateral in micro quote units.
    pub free_margin_micro: Micro,
    /// Realized profit and loss for the current UTC day, micro quote units.
    /// Negative is a loss.
    pub realized_pnl_today_micro: Micro,
    /// Count of consecutive losing closes.
    pub consecutive_losses: u32,
}

impl Portfolio {
    #[must_use]
    pub fn gross_exposure_micro(&self) -> Micro {
        self.positions
            .iter()
            .map(Position::abs_exposure_micro)
            .sum()
    }

    #[must_use]
    pub fn net_exposure_micro(&self) -> Micro {
        self.positions
            .iter()
            .map(Position::signed_exposure_micro)
            .sum()
    }

    #[must_use]
    pub fn exposure_in_market_micro(&self, market: &MarketId) -> Micro {
        self.positions
            .iter()
            .filter(|p| &p.market == market)
            .map(Position::signed_exposure_micro)
            .sum()
    }

    #[must_use]
    pub fn exposure_of_kind_micro(&self, kind: InstrumentKind) -> Micro {
        self.positions
            .iter()
            .filter(|p| p.kind == kind)
            .map(Position::abs_exposure_micro)
            .sum()
    }

    /// Age of the oldest mark price in the book, or None for an empty book.
    #[must_use]
    pub fn worst_mark_age_ms(&self, now_ms: TimestampMs) -> Option<u64> {
        self.positions
            .iter()
            .map(|p| p.mark_price_micro.age_ms(now_ms))
            .max()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn intent(size: i128, price: i128, side: Side) -> OrderIntent {
        OrderIntent {
            market: MarketId::new("TEST-SPOT"),
            kind: InstrumentKind::Spot,
            side,
            size_micro: size,
            limit_price_micro: price,
            decision_id: 1,
        }
    }

    #[test]
    fn notional_scales_correctly() {
        // 2 units at 3 quote each is 6 quote, not 6e6 or 6e-6.
        let i = intent(2 * MICRO, 3 * MICRO, Side::Buy);
        assert_eq!(i.notional_micro(), 6 * MICRO);
    }

    #[test]
    fn sell_notional_is_negative_when_signed() {
        let i = intent(2 * MICRO, 3 * MICRO, Side::Sell);
        assert_eq!(i.notional_micro(), 6 * MICRO);
        assert_eq!(i.signed_notional_micro(), -6 * MICRO);
    }

    #[test]
    fn stale_price_reports_its_age_and_a_backwards_clock_does_not_look_fresh() {
        let p = Stamped::new(1_000 * MICRO, 10_000);
        assert_eq!(p.age_ms(12_500), 2_500);
        assert!(p.is_stale(12_500, 1_000));
        assert!(!p.is_stale(10_500, 1_000));
        // Clock went backwards. Saturating, so age is 0, and critically this
        // must not wrap to u64::MAX which would read as catastrophically stale,
        // nor panic.
        assert_eq!(p.age_ms(9_000), 0);
    }

    #[test]
    fn exposure_nets_and_grosses_differently() {
        let long = Position {
            market: MarketId::new("A"),
            kind: InstrumentKind::Spot,
            net_size_micro: 10 * MICRO,
            mark_price_micro: Stamped::new(100 * MICRO, 0),
        };
        let short = Position {
            market: MarketId::new("B"),
            kind: InstrumentKind::Perp,
            net_size_micro: -4 * MICRO,
            mark_price_micro: Stamped::new(100 * MICRO, 0),
        };
        let pf = Portfolio {
            positions: vec![long, short],
            ..Default::default()
        };
        assert_eq!(pf.gross_exposure_micro(), 1_400 * MICRO);
        assert_eq!(pf.net_exposure_micro(), 600 * MICRO);
        assert_eq!(pf.exposure_of_kind_micro(InstrumentKind::Perp), 400 * MICRO);
    }
}
