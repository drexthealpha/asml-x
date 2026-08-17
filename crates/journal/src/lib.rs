//! Append-only decision journal.
//!
//! This is not logging. It is the product's audit trail and the UI's data source,
//! so it is a core crate rather than an afterthought. Every entry answers, for one
//! decision: what was observed, what was considered, what was chosen, what the risk
//! engine said, what happened onchain, and what it cost.
//!
//! Format is JSON Lines: one self-contained JSON object per line, appended and
//! flushed immediately. Chosen because a crashed process leaves every completed
//! line intact and readable, which a single JSON array would not.

use core_types::TimestampMs;
use serde_json::{json, Value};
use std::fs::{create_dir_all, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

/// One candidate that the decision engine considered, chosen or not.
///
/// Rejected candidates are stored deliberately. A decision record that shows only
/// the winner cannot be distinguished from an if/else ladder, and showing the
/// rejects with their scores is the evidence that a real search happened.
#[derive(Debug, Clone)]
pub struct CandidateRecord {
    pub label: String,
    pub score_micro: i128,
    pub expected_edge_micro: i128,
    pub variance_penalty_micro: i128,
    pub capital_cost_micro: i128,
    pub execution_risk_penalty_micro: i128,
    pub chosen: bool,
    pub rejection_reason: Option<String>,
}

impl CandidateRecord {
    fn to_json(&self) -> Value {
        json!({
            "label": self.label,
            "score_micro": self.score_micro.to_string(),
            "expected_edge_micro": self.expected_edge_micro.to_string(),
            "variance_penalty_micro": self.variance_penalty_micro.to_string(),
            "capital_cost_micro": self.capital_cost_micro.to_string(),
            "execution_risk_penalty_micro": self.execution_risk_penalty_micro.to_string(),
            "chosen": self.chosen,
            "rejection_reason": self.rejection_reason,
        })
    }
}

#[derive(Debug, Clone)]
pub struct SignalRecord {
    pub name: String,
    pub value_micro: i128,
    /// Half-width of the confidence interval, in the same units as value.
    pub confidence_halfwidth_micro: i128,
    pub input_age_ms: u64,
}

impl SignalRecord {
    fn to_json(&self) -> Value {
        json!({
            "name": self.name,
            "value_micro": self.value_micro.to_string(),
            "confidence_halfwidth_micro": self.confidence_halfwidth_micro.to_string(),
            "input_age_ms": self.input_age_ms,
        })
    }
}

/// A complete decision record.
#[derive(Debug, Clone)]
pub struct Entry {
    pub decision_id: u64,
    pub observed_at_ms: TimestampMs,
    pub block_number: u64,
    pub market: String,
    /// Human-readable thesis, generated from the signals rather than templated.
    pub thesis: String,
    pub thesis_confidence_bps: u32,
    pub signals: Vec<SignalRecord>,
    pub candidates: Vec<CandidateRecord>,
    /// What the risk engine returned, verbatim.
    pub risk_verdict: String,
    pub action: Option<String>,
    pub tx_hash: Option<String>,
    pub outcome: Option<String>,
    /// Where every number in this entry came from, so nothing is unattributed.
    pub evidence: Vec<String>,
}

impl Entry {
    fn to_json(&self) -> Value {
        json!({
            "decision_id": self.decision_id,
            "observed_at_ms": self.observed_at_ms,
            "block_number": self.block_number,
            "market": self.market,
            "thesis": self.thesis,
            "thesis_confidence_bps": self.thesis_confidence_bps,
            "signals": self.signals.iter().map(SignalRecord::to_json).collect::<Vec<_>>(),
            "candidates": self.candidates.iter().map(CandidateRecord::to_json).collect::<Vec<_>>(),
            "risk_verdict": self.risk_verdict,
            "action": self.action,
            "tx_hash": self.tx_hash,
            "outcome": self.outcome,
            "evidence": self.evidence,
        })
    }

    /// Count of candidates actually evaluated. The runtime asserts this is never
    /// 1, because a search with one option is not a search.
    #[must_use]
    pub fn candidates_evaluated(&self) -> usize {
        self.candidates.len()
    }
}

/// TASK 14.4. A decision's outcome, recorded against the decision that made the prediction.
///
/// Every field carries the inputs the PnL was computed from, not just the result. A settlement that
/// reported only a number would be unauditable: a reader could not tell a real move from an
/// arithmetic slip, and this project's whole claim is that its numbers can be checked.
#[derive(Debug, Clone)]
pub struct Settlement {
    /// The decision being closed. Joins to `decision_id` in `journal.jsonl`.
    pub decision_id: u64,
    pub settled_at_ms: TimestampMs,
    pub signal_name: String,
    /// "up", "down".
    pub predicted: String,
    pub mid_at_decision: i128,
    pub mid_at_settle: i128,
    pub size_micro: i128,
    pub realized_move_bps: i128,
    pub direction_correct: bool,
    pub expected_edge_micro: i128,
    pub edge_error_micro: i128,
    /// Signed, in micro quote units. Mark to market against `mid_at_settle`, not cash proceeds.
    pub realized_pnl_micro: i128,
}

impl Settlement {
    fn to_json(&self) -> Value {
        json!({
            "record": "settlement",
            "decision_id": self.decision_id,
            "settled_at_ms": self.settled_at_ms,
            "signal_name": self.signal_name,
            "predicted": self.predicted,
            "mid_at_decision": self.mid_at_decision.to_string(),
            "mid_at_settle": self.mid_at_settle.to_string(),
            "size_micro": self.size_micro.to_string(),
            "realized_move_bps": self.realized_move_bps.to_string(),
            "direction_correct": self.direction_correct,
            "expected_edge_micro": self.expected_edge_micro.to_string(),
            "edge_error_micro": self.edge_error_micro.to_string(),
            "realized_pnl_micro": self.realized_pnl_micro.to_string(),
            "basis": "mark to market: size * (mid_at_settle - mid_at_decision), signed by direction",
        })
    }
}

pub struct Journal {
    path: PathBuf,
    next_id: u64,
}

impl Journal {
    /// Open or create the journal, resuming ids from whatever is already on disk so
    /// a restart cannot reuse a decision id and orphan the earlier record.
    pub fn open(path: impl AsRef<Path>) -> std::io::Result<Self> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            create_dir_all(parent)?;
        }
        let next_id = if path.exists() {
            let f = std::fs::File::open(&path)?;
            BufReader::new(f)
                .lines()
                .map_while(Result::ok)
                .filter_map(|l| serde_json::from_str::<Value>(&l).ok())
                .filter_map(|v| v.get("decision_id").and_then(Value::as_u64))
                .max()
                .map_or(1, |m| m + 1)
        } else {
            1
        };
        Ok(Self { path, next_id })
    }

    #[must_use]
    pub const fn next_id(&self) -> u64 {
        self.next_id
    }

    pub fn reserve_id(&mut self) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    /// Append and flush immediately. An unflushed audit trail is not an audit
    /// trail, and the cost of a flush per decision is irrelevant at this cadence.
    pub fn append(&mut self, entry: &Entry) -> std::io::Result<()> {
        let mut f = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)?;
        writeln!(f, "{}", entry.to_json())?;
        f.flush()?;
        if entry.decision_id >= self.next_id {
            self.next_id = entry.decision_id + 1;
        }
        Ok(())
    }

    /// TASK 14.4. Append a settlement, closing the loop on a decision made earlier.
    ///
    /// WHY A SIDECAR AND NOT THE `outcome` FIELD. A decision's outcome is unknown when its row is
    /// written, and the journal is append-only. There were three ways to close that gap and only one
    /// survives contact with the rest of this system:
    ///
    ///   1. Rewrite the original row in place. Rejected outright. Append-only is the property the
    ///      whole evidence chain rests on; a journal that can be edited after the fact cannot be
    ///      cited as a record of what was decided at the time.
    ///   2. Append settlement rows into `journal.jsonl` itself. Rejected on a MEASURED cost, not a
    ///      guess: twenty-odd consumers read that file line by line and index `r["candidates"]` and
    ///      `r["tx_hash"]` directly, so a differently-shaped row breaks the growth counters, the UI
    ///      data build and the scale audit at once.
    ///   3. An append-only sidecar keyed by `decision_id`. Chosen.
    ///
    /// The `outcome` field on a live row stays as it is, and ADR-020 records that it describes
    /// SOMETHING ELSE'S settlement observed during that cycle, which is exactly the confusion this
    /// method removes: a settlement here names the decision that made the prediction.
    pub fn append_settlement(&self, path: impl AsRef<Path>, s: &Settlement) -> std::io::Result<()> {
        let path = path.as_ref();
        if let Some(parent) = path.parent() {
            create_dir_all(parent)?;
        }
        let mut f = OpenOptions::new().create(true).append(true).open(path)?;
        writeln!(f, "{}", s.to_json())?;
        f.flush()
    }

    pub fn read_all(&self) -> std::io::Result<Vec<Value>> {
        if !self.path.exists() {
            return Ok(Vec::new());
        }
        let f = std::fs::File::open(&self.path)?;
        Ok(BufReader::new(f)
            .lines()
            .map_while(Result::ok)
            .filter_map(|l| serde_json::from_str::<Value>(&l).ok())
            .collect())
    }

    pub fn count(&self) -> std::io::Result<usize> {
        Ok(self.read_all()?.len())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "asml-journal-test-{name}-{}.jsonl",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&p);
        p
    }

    fn entry(id: u64, candidates: usize) -> Entry {
        Entry {
            decision_id: id,
            observed_at_ms: 1_000,
            block_number: 42,
            market: "tBASE/tQUOTE".into(),
            thesis: "spread wide relative to realized volatility".into(),
            thesis_confidence_bps: 6_200,
            signals: vec![SignalRecord {
                name: "spread_bps".into(),
                value_micro: 250,
                confidence_halfwidth_micro: 30,
                input_age_ms: 800,
            }],
            candidates: (0..candidates)
                .map(|i| CandidateRecord {
                    label: format!("candidate-{i}"),
                    score_micro: i as i128 * 10,
                    expected_edge_micro: 100,
                    variance_penalty_micro: 10,
                    capital_cost_micro: 5,
                    execution_risk_penalty_micro: 2,
                    chosen: i == candidates - 1,
                    rejection_reason: if i == candidates - 1 {
                        None
                    } else {
                        Some("lower score".into())
                    },
                })
                .collect(),
            risk_verdict: "approved".into(),
            action: Some("take 4e18 base".into()),
            tx_hash: Some("0xabc".into()),
            outcome: None,
            evidence: vec!["eth_call venue.orders(0) at block 42".into()],
        }
    }

    #[test]
    fn append_then_read_roundtrips() {
        let p = tmp("roundtrip");
        let mut j = Journal::open(&p).unwrap();
        j.append(&entry(1, 3)).unwrap();
        j.append(&entry(2, 4)).unwrap();
        let all = j.read_all().unwrap();
        assert_eq!(all.len(), 2);
        assert_eq!(all[0]["decision_id"], 1);
        assert_eq!(all[1]["candidates"].as_array().unwrap().len(), 4);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn ids_resume_after_reopen_so_a_restart_cannot_reuse_one() {
        let p = tmp("resume");
        {
            let mut j = Journal::open(&p).unwrap();
            j.append(&entry(1, 2)).unwrap();
            j.append(&entry(7, 2)).unwrap();
        }
        let j2 = Journal::open(&p).unwrap();
        assert_eq!(j2.next_id(), 8);
        let _ = std::fs::remove_file(&p);
    }

    #[test]
    fn rejected_candidates_are_persisted_with_reasons() {
        // The anti-fake-win property: the record must show what was NOT chosen.
        let e = entry(1, 3);
        let v = e.to_json();
        let cands = v["candidates"].as_array().unwrap();
        assert_eq!(cands.len(), 3);
        let rejected: Vec<_> = cands.iter().filter(|c| c["chosen"] == false).collect();
        assert_eq!(rejected.len(), 2);
        for r in rejected {
            assert!(r["rejection_reason"].is_string());
        }
    }

    #[test]
    fn scores_survive_as_exact_strings_not_lossy_numbers() {
        // i128 exceeds JSON's safe integer range, so scores are serialised as
        // strings. A float round-trip here would corrupt large notionals.
        let mut e = entry(1, 2);
        e.candidates[0].score_micro = i128::MAX;
        let v = e.to_json();
        assert_eq!(v["candidates"][0]["score_micro"], i128::MAX.to_string());
    }
}
