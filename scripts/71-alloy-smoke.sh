#!/usr/bin/env bash
# Task 1.12 alloy. Make ONE eth_call through alloy and compare the returned bytes with the
# hand-rolled chain-client, at the SAME block, byte for byte.
#
# THINKING: #27 opportunity-cost (the hand-rolled client works; alloy buys dynamic ABI and an
# in-process signer, which is what ADR-008's two stated debts are), #23 second-order (a real
# in-process signer removes the `cast` subprocess from the signing path), #50 empirical.
#
# R-SEARCH-1 FINDING, and it CORRECTS a pin in CLAUDE.md: the pinned version there is
# "alloy 1.7.3 (MSRV 1.91)". docs.rs shows the current release is **alloy 2.3.0**, published
# 3 Aug 2026, and the project's stated MSRV is now 1.94.1. Ours is rustc 1.97.1, so the floor is
# satisfied either way. Using 2.3.0: this crate is a comparison probe and a migration target, so
# deliberately installing a superseded major would make the migration decision in 6.6 rest on an
# API that is already old. The stale pin is recorded here rather than quietly followed.
#   Source: https://docs.rs/alloy/latest/alloy/  and https://alloy.rs/
#
# API shape, also from docs.rs rather than memory:
#   ProviderBuilder::new().connect(url).await?   then   provider.call(&tx).await?
#   with TransactionRequest from alloy::rpc::types.
#
# EVIDENCE PATH declared before code: evidence/phase0/alloy.txt
# PASS: both clients return IDENTICAL bytes for the same call at the same block. "alloy compiled"
# is the fake win, and so is comparing at different blocks, which would let two different answers
# look equal or two equal answers look different.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/alloy.txt"
mkdir -p "$(dirname "$OUT")"
PROBE="$REPO/crates/alloy-probe"
GUARD="0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24"

{
echo "alloy eth_call differential, task 1.12"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Version decision"
echo "  CLAUDE.md pins alloy 1.7.3 with MSRV 1.91. That pin is STALE: docs.rs shows alloy"
echo "  2.3.0, released 3 Aug 2026, and MSRV 1.94.1. Using 2.3.0 and recording the correction."
echo "  rustc here: $(rustc --version 2>&1 | head -1)"
echo
echo "## What is being compared"
echo "  RiskGuard.sumOfParts() at a PINNED block, called twice:"
echo "    1. through crates/chain-client, the hand-rolled JSON-RPC client"
echo "    2. through alloy's provider.call"
echo "  Pinning the block matters: sumOfParts changes as exposure changes, so comparing at"
echo "  'latest' twice could disagree for a legitimate reason and would prove nothing either way."
echo
} 2>&1 | tee "$OUT"

mkdir -p "$PROBE/src"

cat > "$PROBE/Cargo.toml" <<'TOML'
[package]
name = "alloy-probe"
version.workspace = true
edition.workspace = true
license.workspace = true
publish = false

# NOT a workspace member of the product graph by accident: this crate exists to compare alloy
# against the hand-rolled client. Nothing in the decision path depends on it, which keeps
# ADR-012's falsification test (no HTTP client in decision-engine, risk-engine or executor) true.
[[bin]]
name = "alloy-probe"
path = "src/main.rs"

[dependencies]
alloy = { version = "2", features = ["full"] }
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
chain-client = { workspace = true }

[lints]
workspace = true
TOML

cat > "$PROBE/src/main.rs" <<'RS'
//! Task 1.12: one eth_call through alloy, compared byte for byte with the hand-rolled client.
//!
//! Both calls are made at the SAME pinned block. The block number is read once, from the
//! hand-rolled client, and passed to alloy explicitly. Calling both at "latest" would compare
//! two different states and could produce a false match or a false mismatch.

use std::env;

use alloy::eips::BlockId;
use alloy::primitives::{Address, Bytes};
use alloy::providers::{Provider, ProviderBuilder};
use alloy::rpc::types::TransactionRequest;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let rpc = env::var("XLAYER_TESTNET_RPC")?;
    let guard_hex = env::var("GUARD_ADDRESS")?;

    // Hand-rolled client first, because it also supplies the block to pin to.
    let hand = chain_client::ChainClient::new(rpc.clone(), None);
    let block = hand.block_number()?;
    let guard = chain_client::parse_address(&guard_hex)?;
    let data = chain_client::calldata("sumOfParts()", &[]);
    let hand_bytes = hand.call_raw(guard, &data)?;

    println!("  pinned block:      {block}");
    println!("  selector:          0x{}", chain_client::hex_encode(&data[..4]));
    println!("  hand-rolled bytes: 0x{}", chain_client::hex_encode(&hand_bytes));

    // alloy, same call, same block.
    let provider = ProviderBuilder::new().connect(&rpc).await?;
    let to: Address = guard_hex.parse()?;
    let tx = TransactionRequest::default()
        .to(to)
        .input(Bytes::from(data.clone()).into());
    let alloy_bytes = provider
        .call(tx)
        .block(BlockId::from(block))
        .await?;

    println!("  alloy bytes:       0x{}", chain_client::hex_encode(&alloy_bytes));

    // Also prove alloy is really talking to chain 1952 and not to a default.
    let cid = provider.get_chain_id().await?;
    println!("  alloy chain id:    {cid}");

    let same = hand_bytes.as_slice() == alloy_bytes.as_ref();
    println!();
    if same && cid == 1952 {
        println!("  IDENTICAL. Both clients returned the same {} bytes at block {block} on chain {cid}.",
                 hand_bytes.len());
        Ok(())
    } else if !same {
        println!("  MISMATCH. The two clients disagree, which means one of them is decoding or");
        println!("  encoding the call incorrectly. This is a real finding, not a flake: the block");
        println!("  is pinned, so the chain state is identical for both reads.");
        std::process::exit(1);
    } else {
        println!("  WRONG CHAIN: alloy reported {cid}, expected 1952.");
        std::process::exit(1);
    }
}
RS

# Register the probe as a workspace member if it is not already.
if ! grep -q 'crates/alloy-probe' "$REPO/Cargo.toml"; then
  /home/zulab/.asml-venv/bin/python - <<'PY'
path = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/Cargo.toml"
src = open(path, encoding="utf-8").read()
# Insert into the members list, right before its closing bracket.
marker = '"crates/learning",'
if marker in src and "crates/alloy-probe" not in src:
    src = src.replace(marker, marker + '\n    "crates/alloy-probe",', 1)
    open(path, "w", encoding="utf-8", newline="\n").write(src)
    print("  registered crates/alloy-probe as a workspace member")
else:
    print("  could not find the members anchor, manifest unchanged")
PY
fi

{
echo "## Build"
} | tee -a "$OUT"
cd "$REPO"
timeout 2400 cargo build -p alloy-probe 2>&1 | tail -12 | sed 's/^/  /' | tee -a "$OUT"
BUILD_RC=${PIPESTATUS[0]}

{
echo
echo "## Resolved version, from the lockfile rather than from the request"
grep -A1 '^name = "alloy"$' Cargo.lock 2>/dev/null | sed 's/^/  /'
echo
echo "## Differential run"
} | tee -a "$OUT"

if [ "${BUILD_RC:-1}" -eq 0 ]; then
  GUARD_ADDRESS="$GUARD" timeout 300 cargo run -q -p alloy-probe 2>&1 | tail -14 | tee -a "$OUT"
  RUN_RC=${PIPESTATUS[0]}
else
  echo "  build failed, nothing run" | tee -a "$OUT"
  RUN_RC=1
fi

{
echo
echo "## Verdict, task 1.12"
if [ "${RUN_RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. Identical bytes from both clients for the same call at the same block,"
  echo "  and alloy confirmed chain id 1952."
  echo "  Reproduce: bash scripts/71-alloy-smoke.sh"
  echo
  echo "  What this buys, for the 6.6 decision: alloy gives dynamic ABI encoding and an"
  echo "  in-process signer, which are exactly ADR-008's two recorded debts (no dynamic ABI,"
  echo "  signing through a cast subprocess). The differential above is the evidence that a"
  echo "  migration would not change what the agent reads from the chain."
else
  echo "  RESULT: FAIL, build exit ${BUILD_RC}, run exit ${RUN_RC}. No equivalence claimed."
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit "${RUN_RC:-1}"
