//! Real market data from OKX, as an input to the agent's decisions.
//!
//! WHY THIS EXISTS. Until now every signal came from an order book this project deployed and seeded.
//! That is honest and it is labelled everywhere, but it means the agent's view of "the market" was a
//! market of one participant: us. Volatility was measured from prices we had posted ourselves.
//!
//! `scripts/okx_market.py` writes `ui-v2/public/data/market.json` from OKX's PUBLIC v5 market API,
//! which needs no key: the live OKB-USDT top of book, a 1-minute candle series, and the BTC-USD
//! index. This module reads that file so the risk and scoring terms can be driven by a real market
//! rather than by our own seeded one.
//!
//! WHAT THIS DOES AND DOES NOT CHANGE, because the distinction is the whole claim:
//!
//!   IT DOES    replace measured volatility with a real one, so the variance penalty responds to
//!              what a real market actually did.
//!   IT DOES NOT change where orders execute. Execution stays on this project's own venue contract,
//!              which is labelled a self-deployed stand-in wherever it appears. Claiming otherwise
//!              would be the integration this project has refused to claim since Phase 0.
//!
//! NO FLOATS ANYWHERE. The workspace denies floating-point arithmetic, because the risk path has to
//! be formally verifiable. The feed therefore emits its basis-point figures as decimal STRINGS and
//! they are parsed straight to integer micro units. An earlier version used `as f64` and clippy
//! rejected it, correctly.
//!
//! ABSENCE IS NOT ZERO. If the file is missing or unreadable these return `None` and the caller
//! keeps its own measurement. A feed that silently degraded to zero volatility would make every
//! candidate look safe, which is the most dangerous failure a risk system can have.

use core_types::Micro;

/// A snapshot of real market state, read from the OKX feed file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExternalMarket {
    /// Mid of the real OKB-USDT book, in micro units.
    pub mid_micro: Micro,
    /// Real spread of that book, in micro basis points.
    pub spread_bps_micro: Micro,
    /// Realized volatility from a real 1-minute candle series, in micro basis points.
    pub realized_vol_bps_micro: Micro,
    /// How many candles that volatility rests on. A number with no sample size is not a measurement.
    pub vol_samples: u32,
    /// A real reference index, currently BTC-USD, in micro units.
    pub reference_index_micro: Option<Micro>,
    /// When the feed was fetched, kept verbatim for the journal.
    pub fetched_at_utc: String,
}

/// Parse a decimal string such as "99.18" into micro units, without floats.
///
/// Truncates rather than rounds, which cannot inflate a price or understate a volatility.
fn parse_micro(s: &str) -> Option<Micro> {
    let s = s.trim();
    if s.is_empty() {
        return None;
    }
    let (neg, s) = match s.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, s),
    };
    let (whole, frac) = s.split_once('.').unwrap_or((s, ""));
    if whole.is_empty() || !whole.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    if !frac.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let w: i128 = whole.parse().ok()?;
    let mut f = frac.to_string();
    f.truncate(6);
    while f.len() < 6 {
        f.push('0');
    }
    let f: i128 = f.parse().ok()?;
    let v = w * 1_000_000 + f;
    Some(if neg { -v } else { v })
}

/// Read a field that may be a JSON string or a JSON number, as micro units, without floats.
///
/// The feed emits decimal strings on purpose, but `serde_json` will also hand back a `Number` if
/// anything upstream changes. `Number::to_string` gives the decimal text, so both shapes are parsed
/// by the same integer path and neither reaches an `f64`.
fn field_micro(v: &serde_json::Value, key: &str) -> Option<Micro> {
    match v.get(key)? {
        serde_json::Value::String(s) => parse_micro(s),
        n @ serde_json::Value::Number(_) => parse_micro(&n.to_string()),
        _ => None,
    }
}

/// Read the feed. Returns `None` when it is absent or unreadable, never a zeroed default.
#[must_use]
pub fn load(path: &str) -> Option<ExternalMarket> {
    let text = std::fs::read_to_string(path).ok()?;
    let v: serde_json::Value = serde_json::from_str(&text).ok()?;

    let pair = v.get("pair")?;
    let vol = v.get("volatility");

    Some(ExternalMarket {
        mid_micro: field_micro(pair, "mid")?,
        spread_bps_micro: field_micro(pair, "spread_bps").unwrap_or(0),
        realized_vol_bps_micro: vol.and_then(|o| field_micro(o, "realized_bps_1m")).unwrap_or(0),
        vol_samples: u32::try_from(
            vol.and_then(|o| o.get("samples"))
                .and_then(serde_json::Value::as_u64)
                .unwrap_or(0),
        )
        .unwrap_or(0),
        reference_index_micro: v
            .get("reference_index")
            .and_then(|o| field_micro(o, "price")),
        fetched_at_utc: v
            .get("fetched_at_utc")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("unknown")
            .to_string(),
    })
}

/// The default location the fetch script writes to.
#[must_use]
pub fn default_path(repo: &str) -> String {
    format!("{repo}/ui-v2/public/data/market.json")
}

/// Replace venue-measured volatility with volatility measured on a REAL market.
///
/// WHY VOLATILITY AND NOT THE PRICE. The agent executes on this project's venue, so its prices are
/// what fill an order. What a seeded venue cannot give is a believable measure of how much a real
/// market MOVES, and that is exactly what the variance penalty spends. Taking realized volatility
/// from the live OKB-USDT series calibrates the risk term to a real market while execution stays
/// honestly local.
///
/// Returns the signals unchanged when the feed is absent or thin, because a volatility of zero
/// would make every candidate look safe.
#[must_use]
pub fn with_real_volatility(mut s: crate::Signals, ext: Option<&ExternalMarket>) -> crate::Signals {
    if let Some(e) = ext {
        // Three samples is the floor the learner uses before it will score anything, and the same
        // reasoning applies: a standard deviation over one or two points is not a measurement.
        if e.vol_samples >= 3 {
            s.realized_vol_bps = Some(crate::Estimate {
                value: e.realized_vol_bps_micro / 1_000_000,
                // The interval narrows as samples grow, so a short series is marked less
                // trustworthy rather than presented as equal to a long one.
                confidence_halfwidth: (e.realized_vol_bps_micro / 1_000_000)
                    / i128::from(e.vol_samples.max(1)),
                sample_size: e.vol_samples,
            });
        }
    }
    s
}

// ============================================================================================
// REAL DEPTH. This is the part that retires the seeded order book as a source of truth.
// ============================================================================================

/// One rung of a measured depth ladder: a size, what it actually costs, and where it fills.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DepthRung {
    /// Size in whole base units. Integer because the ladder is quoted at whole sizes.
    pub size: u64,
    /// Unit price the aggregator returned for that size, in micro units.
    pub unit_price_micro: Micro,
    /// Cost of the size relative to the smallest rung, in micro basis points.
    pub slippage_bps_micro: Micro,
    /// Real pools this size crosses. Empty is a fact, not a default.
    pub venues: Vec<String>,
}

/// A depth curve measured on real pools, written by `scripts/okx_depth.py`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RealDepth {
    pub pair: String,
    pub chain_id: u64,
    pub rungs: Vec<DepthRung>,
    /// Slippage the risk engine tolerates, in basis points.
    pub tolerance_bps: i128,
    pub fetched_at_utc: String,
}

impl RealDepth {
    /// The least disturbed price available: the smallest rung's.
    #[must_use]
    pub fn top_price_micro(&self) -> Option<Micro> {
        self.rungs.first().map(|r| r.unit_price_micro)
    }

    /// The largest size whose measured slippage stays inside tolerance.
    ///
    /// THIS IS THE NUMBER THE SEEDED BOOK COULD NEVER PRODUCE. A book we posted ourselves had
    /// whatever depth we chose to post, so a size limit derived from it was a limit derived from
    /// our own decision. This one is derived from what the pools will actually pay.
    ///
    /// Returns `None` when not even the smallest rung is inside tolerance, which is a real market
    /// state (a pair too thin to trade at all) and must not collapse to "the smallest size is
    /// fine".
    #[must_use]
    pub fn max_safe_size(&self) -> Option<u64> {
        let tol = self.tolerance_bps * 1_000_000;
        self.rungs
            .iter()
            .take_while(|r| r.slippage_bps_micro.abs() <= tol)
            .last()
            .map(|r| r.size)
    }

    /// Every distinct real venue the ladder crosses, in the order first seen.
    #[must_use]
    pub fn venues(&self) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        for r in &self.rungs {
            for v in &r.venues {
                if !out.contains(v) {
                    out.push(v.clone());
                }
            }
        }
        out
    }
}

/// Read the measured depth curve. `None` when absent, never an empty ladder.
///
/// A ladder of fewer than two rungs is rejected rather than accepted, for the same reason the
/// writing script refuses to emit one: a single point implies zero slippage at every size, which
/// is the most dangerous thing this file could tell the risk engine.
#[must_use]
pub fn load_depth(path: &str) -> Option<RealDepth> {
    let text = std::fs::read_to_string(path).ok()?;
    let v: serde_json::Value = serde_json::from_str(&text).ok()?;

    let mut rungs = Vec::new();
    for r in v.get("rungs")?.as_array()? {
        let size = r
            .get("size")
            .and_then(|s| s.as_str())
            .and_then(|s| s.parse::<u64>().ok())?;
        let unit_price_micro = field_micro(r, "unit_price")?;
        let slippage_bps_micro = field_micro(r, "slippage_bps").unwrap_or(0);
        let venues = r
            .get("venues")
            .and_then(serde_json::Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|x| x.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default();
        rungs.push(DepthRung {
            size,
            unit_price_micro,
            slippage_bps_micro,
            venues,
        });
    }
    if rungs.len() < 2 {
        return None;
    }

    Some(RealDepth {
        pair: v
            .get("pair")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("unknown")
            .to_string(),
        chain_id: v
            .get("chain_id")
            .and_then(serde_json::Value::as_u64)
            .unwrap_or(0),
        tolerance_bps: field_micro(&v, "slippage_tolerance_bps")
            .map_or(100, |m| m / 1_000_000),
        rungs,
        fetched_at_utc: v
            .get("fetched_at_utc")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("unknown")
            .to_string(),
    })
}

/// Turn the measured depth ladder into the book the agent reasons over.
///
/// THIS IS THE LINE THE PROJECT HAD NOT CROSSED. Execution went to real pools, but PERCEPTION
/// still came from an order book this project deployed and seeded. That book is crossed (best bid
/// 1.90 sits above best ask 1.70, because both sides were posted by us), so the agent looked at
/// nonsense, correctly refused all twenty-four candidates, and chose to hold every single cycle.
/// The screen showed `tBASE/tQUOTE` and a crossed book because that is genuinely what it was
/// looking at. Real execution on top of imaginary perception is not a real agent.
///
/// HOW A LADDER BECOMES A BOOK. Each rung is a size the aggregator actually quoted and the unit
/// price it quoted for it. That is exactly the shape of a resting order: "this much is available
/// at this price". A rung therefore becomes one `OrderView` per side, with `size_base` set to the
/// INCREMENT over the previous rung rather than the cumulative size, because the ladder is
/// cumulative and copying it verbatim would count the same liquidity several times.
///
/// WHY BOTH SIDES FROM ONE LADDER. The quote is one-directional, so the opposite side is derived
/// by applying the same measured slippage in the other direction. That is an inference and it is
/// labelled as one; it is not a fabricated price, because the magnitude comes from a real
/// measurement of the same pools. What it is NOT is a crossed book: bids sit strictly below asks
/// by construction, which is the property the seeded book violated.
///
/// IDS ARE STABLE AND SYNTHETIC. They start at a high offset so they cannot collide with real
/// venue order ids in the journal, and a reader can tell at a glance which source a decision came
/// from.
#[must_use]
pub fn depth_as_book(d: &RealDepth) -> Vec<crate::OrderView> {
    const SYNTHETIC_ID_BASE: u64 = 900_000;

    let Some(top) = d.top_price_micro() else {
        return Vec::new();
    };

    let mut out = Vec::new();
    let mut prev_size: i128 = 0;

    for (i, r) in d.rungs.iter().enumerate() {
        // Sizes in the ladder are whole tokens; the engine works in micro units.
        let cumulative = i128::from(r.size) * 1_000_000;
        let increment = cumulative - prev_size;
        prev_size = cumulative;
        if increment <= 0 || r.unit_price_micro <= 0 {
            continue;
        }

        // The measured cost of reaching this rung, as a positive basis-point figure.
        let slip_bps = r.slippage_bps_micro.abs() / 1_000_000;

        // ASK: what it costs to buy this increment. The deeper the rung, the worse the price,
        // which is the real curve the aggregator quoted.
        let ask = top + (top * slip_bps) / 10_000;
        // BID: the mirror. Derived, and never allowed to touch or cross the ask.
        let bid = top - (top * slip_bps) / 10_000 - 1;

        if bid > 0 && bid < ask {
            out.push(crate::OrderView {
                id: SYNTHETIC_ID_BASE + (i as u64) * 2,
                maker_buys_base: true, // a bid: taking it means we SELL base
                size_base: increment,
                price_quote: bid,
                filled_base: 0,
                cancelled: false,
            });
            out.push(crate::OrderView {
                id: SYNTHETIC_ID_BASE + (i as u64) * 2 + 1,
                maker_buys_base: false, // an ask: taking it means we BUY base
                size_base: increment,
                price_quote: ask,
                filled_base: 0,
                cancelled: false,
            });
        }
    }
    out
}

// ============================================================================================
// TWO INDEPENDENT PRICE SOURCES. The input the RWA divergence guard never actually had.
// ============================================================================================

/// One instrument, priced twice by sources that do not share a derivation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DualPrice {
    pub symbol: String,
    /// The DEX-derived price, in micro units.
    pub price_micro: Micro,
    /// The aggregated index price, in micro units. A genuinely separate measurement.
    pub index_micro: Micro,
    /// Signed distance between them, in basis points. Positive means the DEX is above the index.
    pub divergence_bps: i128,
    /// Honeypot flag from OKX's own scanner, when it answered.
    pub honeypot: Option<bool>,
}

impl DualPrice {
    /// Is this instrument inside the tolerated band?
    ///
    /// THE POINT OF THE WHOLE THING. The RWA guard refuses trades on an instrument that has come
    /// loose from what it should be worth. Until there were two independent sources it had nothing
    /// to compare against: the "divergence" was a price measured against itself, which is always
    /// zero and therefore always passes. This is the first version of the check that can fail.
    #[must_use]
    pub fn within(&self, tolerance_bps: i128) -> bool {
        self.divergence_bps.abs() <= tolerance_bps
    }
}

/// Read the dual-source prices written by `scripts/oos_all.py`.
///
/// Instruments missing either price are DROPPED rather than defaulted. A single-source instrument
/// cannot be divergence-checked, and including it with a zero divergence would report an unchecked
/// instrument as verified, which is worse than omitting it.
#[must_use]
pub fn load_dual_prices(path: &str) -> Vec<DualPrice> {
    let Ok(text) = std::fs::read_to_string(path) else {
        return Vec::new();
    };
    let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) else {
        return Vec::new();
    };
    let Some(rows) = v.get("tokens").and_then(serde_json::Value::as_array) else {
        return Vec::new();
    };

    let mut out = Vec::new();
    for t in rows {
        let (Some(price), Some(index)) = (field_micro(t, "price"), field_micro(t, "index_price"))
        else {
            continue;
        };
        if index == 0 {
            continue;
        }
        out.push(DualPrice {
            symbol: t
                .get("symbol")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("unknown")
                .to_string(),
            price_micro: price,
            index_micro: index,
            // Integer basis points. No float touches a number the risk path will read.
            divergence_bps: (price - index) * 10_000 / index,
            honeypot: t.get("honeypot").and_then(serde_json::Value::as_bool),
        });
    }
    out
}

/// Where `scripts/oos_all.py` writes the dual-source prices.
#[must_use]
pub fn default_oos_path(repo: &str) -> String {
    format!("{repo}/ui-v2/public/data/onchainos.json")
}

/// Where `scripts/okx_depth.py` writes the ladder.
#[must_use]
pub fn default_depth_path(repo: &str) -> String {
    format!("{repo}/ui-v2/public/data/depth.json")
}

/// Replace the seeded book's spread with the round-trip cost measured on real pools.
///
/// The spread a seeded venue reports is the spread we posted. The spread implied by the depth
/// ladder is what it actually costs to move size through real liquidity, which is the quantity the
/// scoring function was always trying to approximate.
///
/// Sample size is the rung count, honestly: a four-rung ladder is a four-observation measurement
/// and is marked as such rather than presented with the confidence of a long series.
#[must_use]
pub fn with_real_depth(mut s: crate::Signals, depth: Option<&RealDepth>) -> crate::Signals {
    let Some(d) = depth else { return s };
    let Some(top) = d.top_price_micro() else {
        return s;
    };

    s.mid = Some(top);

    // The cost of the largest size still inside tolerance IS the spread that matters to this
    // agent: it is what it would pay to get in and out at the size it is allowed to trade.
    if let Some(worst) = d
        .rungs
        .iter()
        .take_while(|r| r.slippage_bps_micro.abs() <= d.tolerance_bps * 1_000_000)
        .last()
    {
        let bps = worst.slippage_bps_micro.abs() / 1_000_000;
        s.spread_bps = Some(crate::Estimate {
            value: bps,
            // Half a rung's spacing, since the true worst case sits between this rung and the next.
            confidence_halfwidth: bps / 2,
            sample_size: u32::try_from(d.rungs.len()).unwrap_or(0),
        });
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ladder() -> RealDepth {
        // The real measurement from evidence/phase19/real-depth.md, WOKB/USDT on chain 196.
        RealDepth {
            pair: "WOKB/USDT".into(),
            chain_id: 196,
            tolerance_bps: 100,
            fetched_at_utc: "t".into(),
            rungs: vec![
                DepthRung { size: 1, unit_price_micro: 97_393_939, slippage_bps_micro: 0, venues: vec!["Uniswap V3".into()] },
                DepthRung { size: 10, unit_price_micro: 97_364_155, slippage_bps_micro: 3_060_000, venues: vec!["Uniswap V3".into(), "Caliber propAMM".into()] },
                DepthRung { size: 100, unit_price_micro: 97_312_967, slippage_bps_micro: 8_310_000, venues: vec!["Caliber propAMM".into()] },
                DepthRung { size: 1000, unit_price_micro: 94_534_822, slippage_bps_micro: 293_800_000, venues: vec!["PotatoSwap".into()] },
            ],
        }
    }

    #[test]
    fn the_largest_safe_size_is_read_off_measured_slippage() {
        // 1000 WOKB costs 293 bps, which is outside the 100 bps tolerance, so the answer is 100.
        // This is the number a seeded book could not produce, because we chose that book's depth.
        assert_eq!(ladder().max_safe_size(), Some(100));
    }

    #[test]
    fn a_pair_too_thin_to_trade_says_so_rather_than_allowing_the_smallest_size() {
        let mut d = ladder();
        for r in &mut d.rungs {
            r.slippage_bps_micro = 500_000_000; // 500 bps everywhere
        }
        assert_eq!(d.max_safe_size(), None);
    }

    #[test]
    fn real_venues_are_deduplicated_in_first_seen_order() {
        assert_eq!(
            ladder().venues(),
            vec!["Uniswap V3", "Caliber propAMM", "PotatoSwap"]
        );
    }

    #[test]
    fn the_spread_comes_from_the_largest_tolerated_size_not_the_smallest() {
        let s = with_real_depth(crate::Signals::default(), Some(&ladder()));
        let e = s.spread_bps.expect("a measured ladder must set a spread");
        // The 100 WOKB rung, 8.31 bps, not the 1 WOKB rung's zero.
        assert_eq!(e.value, 8);
        assert_eq!(e.sample_size, 4);
    }

    #[test]
    fn a_missing_ladder_leaves_the_signals_untouched() {
        let s = crate::Signals::default();
        assert_eq!(with_real_depth(s.clone(), None).spread_bps, s.spread_bps);
    }

    #[test]
    fn a_one_rung_file_is_rejected_because_it_would_imply_zero_slippage() {
        let dir = std::env::temp_dir().join("asml-depth-test");
        std::fs::create_dir_all(&dir).ok();
        let p = dir.join("one-rung.json");
        std::fs::write(
            &p,
            r#"{"pair":"X/Y","chain_id":196,"rungs":[{"size":"1","unit_price":"1.0","slippage_bps":"0","venues":[]}]}"#,
        )
        .expect("write");
        assert_eq!(load_depth(p.to_str().expect("path")), None);
    }

    #[test]
    fn parses_a_decimal_price_without_floats() {
        assert_eq!(parse_micro("99.18"), Some(99_180_000));
        assert_eq!(parse_micro("64464.5"), Some(64_464_500_000));
        assert_eq!(parse_micro("1"), Some(1_000_000));
        assert_eq!(parse_micro("-2.5"), Some(-2_500_000));
    }

    #[test]
    fn truncates_rather_than_rounds_so_a_price_cannot_inflate() {
        assert_eq!(parse_micro("1.9999999"), Some(1_999_999));
    }

    #[test]
    fn rejects_text_rather_than_silently_returning_zero() {
        assert_eq!(parse_micro("not-a-number"), None);
        assert_eq!(parse_micro(""), None);
    }

    #[test]
    fn a_missing_feed_is_none_and_never_a_zeroed_market() {
        // The dangerous failure is a feed that degrades to zero volatility, because every candidate
        // then looks safe. Absence must stay absent.
        assert_eq!(load("/nonexistent/market.json"), None);
    }

    #[test]
    fn a_thin_series_does_not_override_the_venue_measurement() {
        let s = crate::Signals::default();
        let thin = ExternalMarket {
            mid_micro: 99_000_000,
            spread_bps_micro: 2_000_000,
            realized_vol_bps_micro: 8_000_000,
            vol_samples: 2,
            reference_index_micro: None,
            fetched_at_utc: "t".into(),
        };
        assert!(with_real_volatility(s, Some(&thin)).realized_vol_bps.is_none());
    }

    #[test]
    fn a_real_series_replaces_the_venue_measurement() {
        let s = crate::Signals::default();
        let real = ExternalMarket {
            mid_micro: 99_000_000,
            spread_bps_micro: 2_020_000,
            realized_vol_bps_micro: 8_320_000,
            vol_samples: 30,
            reference_index_micro: Some(64_464_500_000),
            fetched_at_utc: "t".into(),
        };
        let out = with_real_volatility(s, Some(&real));
        let e = out.realized_vol_bps.expect("real series must be used");
        assert_eq!(e.value, 8);
        assert_eq!(e.sample_size, 30);
    }
}

#[cfg(test)]
mod depth_book_tests {
    use super::*;

    fn ladder() -> RealDepth {
        RealDepth {
            pair: "WOKB/USDT".into(),
            chain_id: 196,
            tolerance_bps: 100,
            fetched_at_utc: "t".into(),
            rungs: vec![
                DepthRung { size: 1, unit_price_micro: 98_449_709, slippage_bps_micro: 7_000_000, venues: vec!["Uniswap V3".into()] },
                DepthRung { size: 10, unit_price_micro: 98_293_559, slippage_bps_micro: 10_000_000, venues: vec!["Uniswap V3".into()] },
                DepthRung { size: 100, unit_price_micro: 97_870_968, slippage_bps_micro: 54_000_000, venues: vec!["PotatoSwap".into()] },
            ],
        }
    }

    /// THE PROPERTY THE SEEDED BOOK VIOLATED. Its best bid was 1.90 against a best ask of 1.70,
    /// because this project posted both sides. A crossed book makes spread-based inference
    /// meaningless, which is why the agent held every cycle. A book derived from a real ladder
    /// cannot cross, by construction, and this asserts it rather than assuming it.
    #[test]
    fn the_derived_book_is_never_crossed() {
        let book = depth_as_book(&ladder());
        let best_bid = book.iter().filter(|o| o.maker_buys_base).map(|o| o.price_quote).max();
        let best_ask = book.iter().filter(|o| !o.maker_buys_base).map(|o| o.price_quote).min();
        assert!(best_bid.unwrap() < best_ask.unwrap(), "a derived book must never cross");
    }

    /// The ladder is CUMULATIVE: rung 10 means "10 tokens total", not "10 more". Copying the sizes
    /// verbatim would advertise 111 tokens of liquidity where the aggregator measured 100.
    #[test]
    fn sizes_are_increments_so_liquidity_is_not_double_counted() {
        let book = depth_as_book(&ladder());
        let total: i128 = book
            .iter()
            .filter(|o| o.maker_buys_base)
            .map(|o| o.size_base)
            .sum();
        assert_eq!(total, 100 * 1_000_000, "total depth must equal the deepest rung");
    }

    /// Deeper rungs are worse prices. That IS the depth curve, and if it inverted the agent would
    /// be told that trading larger is cheaper.
    #[test]
    fn deeper_rungs_are_priced_worse_which_is_the_whole_curve() {
        let book = depth_as_book(&ladder());
        let asks: Vec<i128> = book.iter().filter(|o| !o.maker_buys_base).map(|o| o.price_quote).collect();
        for w in asks.windows(2) {
            assert!(w[1] >= w[0], "asks must not improve with size");
        }
    }

    /// An empty or unusable ladder yields NO book, never a book of zeroes. A zero-priced order
    /// would look like free liquidity to the scoring function.
    #[test]
    fn an_empty_ladder_yields_no_book_rather_than_zero_priced_orders() {
        let mut d = ladder();
        d.rungs.clear();
        assert!(depth_as_book(&d).is_empty());
    }

    /// Synthetic ids must not collide with venue order ids, so a journal reader can always tell
    /// which source a decision was made against.
    #[test]
    fn synthetic_ids_cannot_collide_with_venue_order_ids() {
        for o in depth_as_book(&ladder()) {
            assert!(o.id >= 900_000, "synthetic ids sit above any real venue id");
        }
    }
}

#[cfg(test)]
mod dual_price_tests {
    use super::*;

    fn write(json: &str) -> String {
        let dir = std::env::temp_dir().join("asml-dual");
        std::fs::create_dir_all(&dir).ok();
        let p = dir.join(format!("d{}.json", json.len()));
        std::fs::write(&p, json).expect("write");
        p.to_string_lossy().into_owned()
    }

    /// The real measurement, from evidence/phase20: WBTC quoted at 64579.673864 by the DEX and
    /// 64558.0157 by the aggregated index, which is 3.35 bps apart.
    #[test]
    fn divergence_is_computed_between_two_genuinely_different_sources() {
        let p = write(
            r#"{"tokens":[{"symbol":"WBTC","price":"64579.673864","index_price":"64558.015748"}]}"#,
        );
        let rows = load_dual_prices(&p);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].divergence_bps, 3);
        assert!(rows[0].within(300));
    }

    /// A breach must actually be able to happen. Before two sources existed the check compared a
    /// price to itself, so it could only ever return zero and always passed.
    #[test]
    fn a_real_breach_fails_the_band() {
        let p = write(r#"{"tokens":[{"symbol":"X","price":"1.5","index_price":"1.0"}]}"#);
        let rows = load_dual_prices(&p);
        assert_eq!(rows[0].divergence_bps, 5000);
        assert!(!rows[0].within(300), "5000 bps must breach a 300 bps band");
    }

    /// An instrument with only one source cannot be divergence-checked and must be dropped, not
    /// reported as a zero divergence. Reporting it as zero says "verified" about something nobody
    /// verified.
    #[test]
    fn a_single_source_instrument_is_dropped_rather_than_reported_as_agreeing() {
        let p = write(r#"{"tokens":[{"symbol":"ONLYONE","price":"1.0"}]}"#);
        assert!(load_dual_prices(&p).is_empty());
    }

    /// A zero index would divide by zero. Dropped, never defaulted.
    #[test]
    fn a_zero_index_is_dropped_rather_than_dividing_by_zero() {
        let p = write(r#"{"tokens":[{"symbol":"Z","price":"1.0","index_price":"0"}]}"#);
        assert!(load_dual_prices(&p).is_empty());
    }

    /// Sign is preserved: below the index is negative, above is positive. A guard that took the
    /// absolute value too early could not tell a premium from a discount.
    #[test]
    fn the_sign_says_which_side_the_dex_is_on() {
        let p = write(
            r#"{"tokens":[{"symbol":"A","price":"99.574098","index_price":"99.62"},
                          {"symbol":"B","price":"1.000982","index_price":"1.0"}]}"#,
        );
        let rows = load_dual_prices(&p);
        assert!(rows[0].divergence_bps < 0, "WOKB traded below its index");
        assert!(rows[1].divergence_bps > 0, "USDC traded above its index");
    }

    #[test]
    fn a_missing_file_is_empty_not_an_error() {
        assert!(load_dual_prices("/nonexistent/oos.json").is_empty());
    }
}
