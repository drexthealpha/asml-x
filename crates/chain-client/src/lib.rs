//! Minimal JSON-RPC client for X Layer testnet, chain 1952.
//!
//! Why hand-rolled ABI coding rather than alloy or ethers: the runtime needs
//! exactly five read shapes (uint256, address, bool, bytes32, and one static
//! struct) and no dynamic types at all. Encoding those is about eighty lines with
//! no ambiguity, against a dependency tree that dominates build time for the whole
//! workspace. The tradeoff is recorded in ADR-008. If dynamic types are ever
//! needed, replace this module with alloy-sol-types rather than extending it,
//! because hand-rolled dynamic encoding is where the real bugs live.
//!
//! Signing is NOT done here. See ADR-008: transaction signing is delegated to
//! `cast` as a subprocess, stated plainly rather than wrapped to look native.

use core_types::TimestampMs;
use std::fmt;

pub type Address = [u8; 20];
pub type Word = [u8; 32];

#[derive(Debug)]
pub enum ChainError {
    Transport(String),
    Rpc { code: i64, message: String },
    Decode(String),
}

impl fmt::Display for ChainError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ChainError::Transport(s) => write!(f, "transport: {s}"),
            ChainError::Rpc { code, message } => write!(f, "rpc {code}: {message}"),
            ChainError::Decode(s) => write!(f, "decode: {s}"),
        }
    }
}

impl std::error::Error for ChainError {}

// ---------------------------------------------------------------------------
// hex and ABI helpers
// ---------------------------------------------------------------------------

#[must_use]
pub fn hex_encode(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(2 + bytes.len() * 2);
    s.push_str("0x");
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

pub fn hex_decode(s: &str) -> Result<Vec<u8>, ChainError> {
    let s = s.strip_prefix("0x").unwrap_or(s);
    if !s.len().is_multiple_of(2) {
        return Err(ChainError::Decode(format!("odd hex length {}", s.len())));
    }
    (0..s.len())
        .step_by(2)
        .map(|i| {
            u8::from_str_radix(&s[i..i + 2], 16)
                .map_err(|e| ChainError::Decode(format!("bad hex: {e}")))
        })
        .collect()
}

pub fn parse_address(s: &str) -> Result<Address, ChainError> {
    let v = hex_decode(s)?;
    if v.len() != 20 {
        return Err(ChainError::Decode(format!(
            "address must be 20 bytes, got {}",
            v.len()
        )));
    }
    let mut a = [0u8; 20];
    a.copy_from_slice(&v);
    Ok(a)
}

pub fn parse_word(s: &str) -> Result<Word, ChainError> {
    let v = hex_decode(s)?;
    if v.len() != 32 {
        return Err(ChainError::Decode(format!(
            "word must be 32 bytes, got {}",
            v.len()
        )));
    }
    let mut w = [0u8; 32];
    w.copy_from_slice(&v);
    Ok(w)
}

/// Left-pad a u128 into a 32 byte word.
#[must_use]
pub fn word_from_u128(v: u128) -> Word {
    let mut w = [0u8; 32];
    w[16..].copy_from_slice(&v.to_be_bytes());
    w
}

#[must_use]
pub fn word_from_address(a: Address) -> Word {
    let mut w = [0u8; 32];
    w[12..].copy_from_slice(&a);
    w
}

/// Decode a 32 byte word as u128, rejecting anything that does not fit.
///
/// Rejecting rather than truncating is deliberate. A silent truncation of a
/// uint256 into a u128 is exactly the class of bug that makes a risk check read a
/// huge exposure as a small one.
pub fn u128_from_word(w: &[u8]) -> Result<u128, ChainError> {
    if w.len() != 32 {
        return Err(ChainError::Decode(format!(
            "expected 32 bytes, got {}",
            w.len()
        )));
    }
    if w[..16].iter().any(|b| *b != 0) {
        return Err(ChainError::Decode(
            "uint256 exceeds u128, refusing to truncate".to_string(),
        ));
    }
    let mut b = [0u8; 16];
    b.copy_from_slice(&w[16..]);
    Ok(u128::from_be_bytes(b))
}

pub fn bool_from_word(w: &[u8]) -> Result<bool, ChainError> {
    Ok(u128_from_word(w)? != 0)
}

// ---------------------------------------------------------------------------
// keccak256, needed for function selectors
// ---------------------------------------------------------------------------

/// keccak256 via tiny-keccak. Deliberately not hand-rolled: a subtly wrong hash
/// would produce wrong function selectors, and wrong selectors fail in ways that
/// look like contract bugs. R16 says integrate the existing implementation.
#[must_use]
pub fn keccak256(input: &[u8]) -> [u8; 32] {
    use tiny_keccak::{Hasher, Keccak};
    let mut h = Keccak::v256();
    let mut out = [0u8; 32];
    h.update(input);
    h.finalize(&mut out);
    out
}

/// First four bytes of keccak256 of the canonical signature.
#[must_use]
pub fn selector(signature: &str) -> [u8; 4] {
    let h = keccak256(signature.as_bytes());
    [h[0], h[1], h[2], h[3]]
}

/// Build calldata from a signature and pre-encoded static words.
#[must_use]
pub fn calldata(signature: &str, args: &[Word]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + args.len() * 32);
    out.extend_from_slice(&selector(signature));
    for a in args {
        out.extend_from_slice(a);
    }
    out
}

// ---------------------------------------------------------------------------
// client
// ---------------------------------------------------------------------------

pub struct ChainClient {
    rpc_url: String,
    fallback_url: Option<String>,
    next_id: std::cell::Cell<u64>,
}

impl ChainClient {
    #[must_use]
    pub fn new(rpc_url: impl Into<String>, fallback_url: Option<String>) -> Self {
        Self {
            rpc_url: rpc_url.into(),
            fallback_url,
            next_id: std::cell::Cell::new(1),
        }
    }

    fn post(&self, url: &str, body: serde_json::Value) -> Result<serde_json::Value, ChainError> {
        let resp = ureq::post(url)
            .set("content-type", "application/json")
            .timeout(std::time::Duration::from_secs(15))
            .send_json(body)
            .map_err(|e| ChainError::Transport(e.to_string()))?;
        let v: serde_json::Value = resp
            .into_json()
            .map_err(|e| ChainError::Transport(e.to_string()))?;
        if let Some(err) = v.get("error") {
            return Err(ChainError::Rpc {
                code: err
                    .get("code")
                    .and_then(serde_json::Value::as_i64)
                    .unwrap_or(0),
                message: err
                    .get("message")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("unknown")
                    .to_string(),
            });
        }
        v.get("result")
            .cloned()
            .ok_or_else(|| ChainError::Decode("no result field".into()))
    }

    /// Call with an automatic single failover to the fallback endpoint.
    ///
    /// One failover, not a retry loop. A retry loop here would mask a dead
    /// endpoint, and the risk engine needs to see `rpc_failed` rather than sit in
    /// a loop believing the world is fine.
    fn rpc(
        &self,
        method: &str,
        params: serde_json::Value,
    ) -> Result<serde_json::Value, ChainError> {
        let id = self.next_id.get();
        self.next_id.set(id + 1);
        let body = serde_json::json!({
            "jsonrpc": "2.0", "id": id, "method": method, "params": params
        });
        match self.post(&self.rpc_url, body.clone()) {
            Ok(v) => Ok(v),
            Err(primary_err) => match &self.fallback_url {
                Some(f) => self.post(f, body).map_err(|_| primary_err),
                None => Err(primary_err),
            },
        }
    }

    pub fn chain_id(&self) -> Result<u64, ChainError> {
        let v = self.rpc("eth_chainId", serde_json::json!([]))?;
        let s = v
            .as_str()
            .ok_or_else(|| ChainError::Decode("chainId not a string".into()))?;
        u64::from_str_radix(s.trim_start_matches("0x"), 16)
            .map_err(|e| ChainError::Decode(e.to_string()))
    }

    pub fn block_number(&self) -> Result<u64, ChainError> {
        let v = self.rpc("eth_blockNumber", serde_json::json!([]))?;
        let s = v
            .as_str()
            .ok_or_else(|| ChainError::Decode("blockNumber not a string".into()))?;
        u64::from_str_radix(s.trim_start_matches("0x"), 16)
            .map_err(|e| ChainError::Decode(e.to_string()))
    }

    /// Latest block timestamp in milliseconds.
    ///
    /// The runtime uses chain time, not wall time, for staleness. Wall time would
    /// make the agent think data is fresh when the chain has stopped producing
    /// blocks, which is precisely the condition the kill switch must catch.
    pub fn block_timestamp_ms(&self) -> Result<TimestampMs, ChainError> {
        let v = self.rpc("eth_getBlockByNumber", serde_json::json!(["latest", false]))?;
        let ts = v
            .get("timestamp")
            .and_then(serde_json::Value::as_str)
            .ok_or_else(|| ChainError::Decode("no timestamp".into()))?;
        let secs = u64::from_str_radix(ts.trim_start_matches("0x"), 16)
            .map_err(|e| ChainError::Decode(e.to_string()))?;
        Ok(secs.saturating_mul(1000))
    }

    pub fn call_raw(&self, to: Address, data: &[u8]) -> Result<Vec<u8>, ChainError> {
        let v = self.rpc(
            "eth_call",
            serde_json::json!([{ "to": hex_encode(&to), "data": hex_encode(data) }, "latest"]),
        )?;
        let s = v
            .as_str()
            .ok_or_else(|| ChainError::Decode("call result not a string".into()))?;
        hex_decode(s)
    }

    /// Single-word call, the common case.
    pub fn call_word(
        &self,
        to: Address,
        signature: &str,
        args: &[Word],
    ) -> Result<Word, ChainError> {
        let out = self.call_raw(to, &calldata(signature, args))?;
        if out.len() < 32 {
            return Err(ChainError::Decode(format!(
                "expected at least 32 bytes from {signature}, got {}",
                out.len()
            )));
        }
        let mut w = [0u8; 32];
        w.copy_from_slice(&out[..32]);
        Ok(w)
    }

    pub fn call_u128(
        &self,
        to: Address,
        signature: &str,
        args: &[Word],
    ) -> Result<u128, ChainError> {
        let w = self.call_word(to, signature, args)?;
        u128_from_word(&w)
    }

    pub fn call_bool(
        &self,
        to: Address,
        signature: &str,
        args: &[Word],
    ) -> Result<bool, ChainError> {
        let w = self.call_word(to, signature, args)?;
        bool_from_word(&w)
    }

    /// Multi-word call for static structs, such as `orders(uint256)`.
    pub fn call_words(
        &self,
        to: Address,
        signature: &str,
        args: &[Word],
        expect: usize,
    ) -> Result<Vec<Word>, ChainError> {
        let out = self.call_raw(to, &calldata(signature, args))?;
        if out.len() < expect * 32 {
            return Err(ChainError::Decode(format!(
                "expected {} words from {signature}, got {} bytes",
                expect,
                out.len()
            )));
        }
        Ok(out
            .chunks_exact(32)
            .take(expect)
            .map(|c| {
                let mut w = [0u8; 32];
                w.copy_from_slice(c);
                w
            })
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selector_matches_known_values() {
        // Known-good selectors, cross-checked against `cast sig`.
        assert_eq!(
            hex_encode(&selector("transfer(address,uint256)")),
            "0xa9059cbb"
        );
        assert_eq!(hex_encode(&selector("balanceOf(address)")), "0x70a08231");
        assert_eq!(hex_encode(&selector("totalSupply()")), "0x18160ddd");
        assert_eq!(
            hex_encode(&selector("approve(address,uint256)")),
            "0x095ea7b3"
        );
    }

    #[test]
    fn u128_from_word_refuses_to_truncate() {
        // A uint256 that does not fit in u128 must error, never silently wrap to a
        // small number that a risk check would happily approve.
        let mut big = [0u8; 32];
        big[0] = 1;
        assert!(u128_from_word(&big).is_err());

        let ok = word_from_u128(42);
        assert_eq!(u128_from_word(&ok).unwrap(), 42);

        let max = word_from_u128(u128::MAX);
        assert_eq!(u128_from_word(&max).unwrap(), u128::MAX);
    }

    #[test]
    fn address_words_are_left_padded() {
        let a = parse_address("0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46").unwrap();
        let w = word_from_address(a);
        assert_eq!(&w[..12], &[0u8; 12]);
        assert_eq!(&w[12..], &a);
    }

    #[test]
    fn hex_roundtrips() {
        let s = "0xdeadbeef";
        assert_eq!(hex_encode(&hex_decode(s).unwrap()), s);
    }

    #[test]
    fn calldata_layout_is_selector_then_words() {
        let d = calldata("balanceOf(address)", &[word_from_u128(1)]);
        assert_eq!(d.len(), 36);
        assert_eq!(hex_encode(&d[..4]), "0x70a08231");
    }
}
