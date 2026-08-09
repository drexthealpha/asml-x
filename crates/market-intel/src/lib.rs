//! Market Intelligence. Task 4.1.
//!
//! Reads the real order book from chain 1952 and turns it into signals. Three
//! rules hold throughout, and they are what separate a signal from decoration:
//!
//! 1. Every signal carries a confidence half-width. A point estimate with no
//!    stated uncertainty invites the decision engine to treat noise as edge.
//! 2. Every signal carries the age of its inputs, taken from chain time rather
//!    than wall time. Wall time would report data as fresh while the chain is
//!    stalled, which is exactly the condition the kill switch must catch.
//! 3. A signal that cannot be computed is `None`, never a default. A zero spread
//!    and an unknown spread must never be the same value.

use chain_client::{word_from_u128, Address, ChainClient, ChainError};
use core_types::{Micro, Stamped, TimestampMs, MICRO};

/// One resting order as read from the venue.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrderView {
    pub id: u64,
    pub maker_buys_base: bool,
    pub size_base: Micro,
    pub price_quote: Micro,
    pub filled_base: Micro,
    pub cancelled: bool,
}

impl OrderView {
    #[must_use]
    pub const fn remaining_base(&self) -> Micro {
        if self.cancelled {
            0
        } else {
            self.size_base - self.filled_base
        }
    }

    #[must_use]
    pub const fn is_live(&self) -> bool {
        !self.cancelled && self.remaining_base() > 0
    }
}

/// A point-in-time view of the venue, stamped with the chain state it came from.
#[derive(Debug, Clone)]
pub struct VenueSnapshot {
    pub orders: Vec<OrderView>,
    pub block_number: u64,
    pub chain_time_ms: TimestampMs,
}

/// Wei per micro-unit. The chain speaks 18 decimals, the risk engine speaks 6.
///
/// This constant is the entire bridge between those two worlds and it exists in
/// exactly one place on purpose. The first live run refused 10 of 11 candidates
/// every cycle because raw 18-decimal values were fed to a 6-decimal risk engine,
/// making every notional look about 1e24 times too large. That failure was silent
/// and looked exactly like a conservative agent behaving correctly, which is what
/// made it dangerous.
pub const WEI_PER_MICRO: i128 = 1_000_000_000_000;

/// Convert an 18-decimal chain amount to a 6-decimal micro amount.
///
/// Truncating division, and that is deliberate: rounding up would let a size pass a
/// risk check by a hair that the chain then exceeds.
#[must_use]
pub const fn wei_to_micro(wei: i128) -> Micro {
    wei / WEI_PER_MICRO
}

/// Convert a 6-decimal micro amount back to an 18-decimal chain amount.
#[must_use]
pub const fn micro_to_wei(micro: Micro) -> i128 {
    micro * WEI_PER_MICRO
}

/// Read every order from the venue.
///
/// Reads sequentially rather than through Multicall3. Multicall3 is deployed at
/// 0xcA11...CA11 on this chain and would be the right optimisation at a few hundred
/// orders, but batching a dynamic-length array of calls requires dynamic ABI
/// encoding, which ADR-008 deliberately keeps out of the hand-rolled client. Stated
/// as a known limitation rather than hidden: at the order counts this demo runs,
/// sequential reads cost milliseconds.
pub fn read_snapshot(client: &ChainClient, venue: Address) -> Result<VenueSnapshot, ChainError> {
    let block_number = client.block_number()?;
    let chain_time_ms = client.block_timestamp_ms()?;
    let count = client.call_u128(venue, "orderCount()", &[])?;

    let mut orders = Vec::with_capacity(count as usize);
    for i in 0..count {
        // orders(uint256) returns 8 static words:
        // maker, base, quote, makerBuysBase, sizeBase, priceQuote, filledBase, cancelled
        let w = client.call_words(venue, "orders(uint256)", &[word_from_u128(i)], 8)?;
        orders.push(OrderView {
            id: i as u64,
            maker_buys_base: chain_client::bool_from_word(&w[3])?,
            // Normalised to micro-units at the boundary, so nothing downstream ever
            // sees an 18-decimal number. See WEI_PER_MICRO.
            size_base: wei_to_micro(
                i128::try_from(chain_client::u128_from_word(&w[4])?)
                    .map_err(|_| ChainError::Decode("sizeBase exceeds i128".into()))?,
            ),
            price_quote: wei_to_micro(
                i128::try_from(chain_client::u128_from_word(&w[5])?)
                    .map_err(|_| ChainError::Decode("priceQuote exceeds i128".into()))?,
            ),
            filled_base: wei_to_micro(
                i128::try_from(chain_client::u128_from_word(&w[6])?)
                    .map_err(|_| ChainError::Decode("filledBase exceeds i128".into()))?,
            ),
            cancelled: chain_client::bool_from_word(&w[7])?,
        });
    }

    Ok(VenueSnapshot {
        orders,
        block_number,
        chain_time_ms,
    })
}

/// A single estimate with stated uncertainty.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Estimate {
    pub value: Micro,
    /// Half-width of the interval. Larger means less trustworthy.
    pub confidence_halfwidth: Micro,
    pub sample_size: u32,
}

impl Estimate {
    #[must_use]
    pub const fn new(value: Micro, halfwidth: Micro, sample_size: u32) -> Self {
        Self {
            value,
            confidence_halfwidth: halfwidth,
            sample_size,
        }
    }

    /// Confidence in basis points, derived from how wide the interval is relative
    /// to the estimate. Deliberately crude and monotone rather than a fake
    /// statistical guarantee: it says "wider interval means less confidence" and
    /// claims nothing more.
    #[must_use]
    pub fn confidence_bps(&self) -> u32 {
        if self.value == 0 {
            return 0;
        }
        let rel = (self.confidence_halfwidth.abs() * 10_000) / self.value.abs().max(1);
        u32::try_from(10_000i128.saturating_sub(rel).max(0)).unwrap_or(0)
    }
}

/// The signal set for one market. Every field is optional because an unknown
/// signal must be distinguishable from a zero one.
#[derive(Debug, Clone, Default)]
pub struct Signals {
    pub best_bid: Option<Micro>,
    pub best_ask: Option<Micro>,
    pub mid: Option<Micro>,
    /// Spread in basis points of mid.
    pub spread_bps: Option<Estimate>,
    /// Total live base on each side.
    pub bid_depth_base: Micro,
    pub ask_depth_base: Micro,
    /// Order flow imbalance in basis points: positive means bid-heavy.
    pub imbalance_bps: Option<Estimate>,
    /// Realized volatility of mid, in basis points, over the mid history.
    pub realized_vol_bps: Option<Estimate>,
    pub live_order_count: u32,
    pub input_age_ms: u64,
}

/// Rolling estimator. Holds mid history so volatility is measured rather than
/// assumed.
#[derive(Debug, Clone, Default)]
pub struct MarketIntel {
    mid_history: Vec<Stamped<Micro>>,
    max_history: usize,
}

impl MarketIntel {
    #[must_use]
    pub fn new(max_history: usize) -> Self {
        Self {
            mid_history: Vec::new(),
            max_history: max_history.max(2),
        }
    }

    #[must_use]
    pub fn history_len(&self) -> usize {
        self.mid_history.len()
    }

    /// Compute signals from a snapshot, updating internal history.
    pub fn observe(&mut self, snap: &VenueSnapshot, now_ms: TimestampMs) -> Signals {
        let live: Vec<&OrderView> = snap.orders.iter().filter(|o| o.is_live()).collect();

        // A maker buying base is a bid. A maker selling base is an ask.
        let best_bid = live
            .iter()
            .filter(|o| o.maker_buys_base)
            .map(|o| o.price_quote)
            .max();
        let best_ask = live
            .iter()
            .filter(|o| !o.maker_buys_base)
            .map(|o| o.price_quote)
            .min();

        let bid_depth_base: Micro = live
            .iter()
            .filter(|o| o.maker_buys_base)
            .map(|o| o.remaining_base())
            .sum();
        let ask_depth_base: Micro = live
            .iter()
            .filter(|o| !o.maker_buys_base)
            .map(|o| o.remaining_base())
            .sum();

        let mid = match (best_bid, best_ask) {
            (Some(b), Some(a)) => Some((b + a) / 2),
            // One-sided book: the single side is the best available reference, and
            // the wide confidence interval below is what tells the decision engine
            // not to trust it as a mid.
            (Some(b), None) => Some(b),
            (None, Some(a)) => Some(a),
            (None, None) => None,
        };

        let spread_bps = match (best_bid, best_ask, mid) {
            (Some(b), Some(a), Some(m)) if m > 0 => {
                let spread = a - b;
                let bps = (spread * 10_000) / m;
                // Uncertainty grows when the book is thin. Two orders on a side is
                // not the same evidence as twenty.
                let n = live.len() as i128;
                let halfwidth = if n >= 2 { bps.abs() / n } else { bps.abs() };
                Some(Estimate::new(bps, halfwidth, live.len() as u32))
            }
            _ => None,
        };

        let imbalance_bps = {
            let total = bid_depth_base + ask_depth_base;
            if total > 0 {
                let imb = ((bid_depth_base - ask_depth_base) * 10_000) / total;
                let n = live.len().max(1) as i128;
                Some(Estimate::new(imb, imb.abs() / n, live.len() as u32))
            } else {
                None
            }
        };

        if let Some(m) = mid {
            self.mid_history.push(Stamped::new(m, snap.chain_time_ms));
            if self.mid_history.len() > self.max_history {
                let excess = self.mid_history.len() - self.max_history;
                self.mid_history.drain(0..excess);
            }
        }

        let realized_vol_bps = self.realized_vol_bps();

        let input_age_ms = now_ms.saturating_sub(snap.chain_time_ms);

        Signals {
            best_bid,
            best_ask,
            mid,
            spread_bps,
            bid_depth_base,
            ask_depth_base,
            imbalance_bps,
            realized_vol_bps,
            live_order_count: live.len() as u32,
            input_age_ms,
        }
    }

    /// Mean absolute return of mid, in basis points.
    ///
    /// Mean absolute deviation rather than standard deviation, because integer
    /// square roots on i128 would add a fixed-point approximation for no benefit at
    /// this sample size. Stated so nobody reads "vol" as a Gaussian sigma.
    fn realized_vol_bps(&self) -> Option<Estimate> {
        if self.mid_history.len() < 3 {
            return None;
        }
        let mut sum_abs_bps: i128 = 0;
        let mut n: i128 = 0;
        for pair in self.mid_history.windows(2) {
            let prev = pair[0].value;
            let cur = pair[1].value;
            if prev <= 0 {
                continue;
            }
            sum_abs_bps += ((cur - prev).abs() * 10_000) / prev;
            n += 1;
        }
        if n == 0 {
            return None;
        }
        let mean = sum_abs_bps / n;
        // Standard-error-like shrinkage: more samples, tighter interval.
        let halfwidth = mean / n.max(1);
        Some(Estimate::new(mean, halfwidth, n as u32))
    }

    /// A one-line thesis generated from the signals themselves.
    ///
    /// Built from the actual numbers, never from a template with values pasted in,
    /// so it cannot claim something the signals do not support.
    #[must_use]
    pub fn thesis(signals: &Signals) -> (String, u32) {
        let mut parts: Vec<String> = Vec::new();
        let mut confidences: Vec<u32> = Vec::new();

        // A crossed book is disclosed first and loudly. It means the best bid sits above
        // the best ask, which on a real venue would be arbitrage and here means the
        // simulator posted a level through the resting side. Either way it invalidates
        // every spread-derived inference below it, so saying so is the honest thing
        // rather than reporting a negative spread as if it were a tight one.
        let mut crossed = false;
        if let (Some(b), Some(a)) = (signals.best_bid, signals.best_ask) {
            if b >= a {
                crossed = true;
                parts.push(format!(
                    "BOOK IS CROSSED: best bid {} is at or above best ask {}, so spread-based inference is unreliable",
                    fmt_micro(b),
                    fmt_micro(a)
                ));
            }
        }

        match (&signals.spread_bps, &signals.realized_vol_bps) {
            (Some(s), Some(v)) => {
                confidences.push(s.confidence_bps());
                confidences.push(v.confidence_bps());
                if s.value > v.value * 2 {
                    parts.push(format!(
                        "spread {} bps is more than twice realized volatility {} bps, so quoting is paid for the risk it takes",
                        s.value, v.value
                    ));
                } else if s.value < v.value {
                    parts.push(format!(
                        "spread {} bps is below realized volatility {} bps, so quoting is underpaid",
                        s.value, v.value
                    ));
                } else {
                    parts.push(format!(
                        "spread {} bps is comparable to realized volatility {} bps",
                        s.value, v.value
                    ));
                }
            }
            (Some(s), None) => {
                confidences.push(s.confidence_bps() / 2);
                parts.push(format!(
                    "spread {} bps observed, volatility not yet estimable, fewer than three mid observations so far",
                    s.value
                ));
            }
            _ => parts.push("book is one-sided or empty, no spread to assess".to_string()),
        }

        if let Some(i) = &signals.imbalance_bps {
            confidences.push(i.confidence_bps());
            if i.value.abs() > 2_000 {
                parts.push(format!(
                    "depth is {} by {} bps",
                    if i.value > 0 {
                        "bid-heavy"
                    } else {
                        "ask-heavy"
                    },
                    i.value.abs()
                ));
            }
        }

        if signals.input_age_ms > 10_000 {
            parts.push(format!(
                "inputs are {} ms old, which weakens every claim above",
                signals.input_age_ms
            ));
            confidences.push(0);
        }

        // A crossed book ZEROES confidence rather than diluting it. Averaging a single
        // zero into the other terms still left 833 bps of confidence on a book whose
        // spread is meaningless, which is worse than useless: it is a confident claim
        // built on an invalid input.
        let confidence = if crossed || confidences.is_empty() {
            0
        } else {
            confidences.iter().sum::<u32>() / confidences.len() as u32
        };
        (parts.join("; "), confidence)
    }
}

/// Convert a micro value to a human string with 6 decimal places, for UI and docs.
#[must_use]
pub fn fmt_micro(v: Micro) -> String {
    let sign = if v < 0 { "-" } else { "" };
    let a = v.abs();
    format!("{sign}{}.{:06}", a / MICRO, a % MICRO)
}

#[cfg(test)]
mod tests;
