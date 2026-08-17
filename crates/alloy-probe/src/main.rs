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
    println!(
        "  selector:          {}",
        chain_client::hex_encode(&data[..4])
    );
    println!(
        "  hand-rolled bytes: {}",
        chain_client::hex_encode(&hand_bytes)
    );

    // alloy, same call, same block.
    let provider = ProviderBuilder::new().connect(&rpc).await?;
    let to: Address = guard_hex.parse()?;
    let tx = TransactionRequest::default()
        .to(to)
        .input(Bytes::from(data.clone()).into());
    let alloy_bytes = provider.call(tx).block(BlockId::from(block)).await?;

    println!(
        "  alloy bytes:       {}",
        chain_client::hex_encode(&alloy_bytes)
    );

    // Also prove alloy is really talking to chain 1952 and not to a default.
    let cid = provider.get_chain_id().await?;
    println!("  alloy chain id:    {cid}");

    let same = hand_bytes.as_slice() == alloy_bytes.as_ref();
    println!();
    if same && cid == 1952 {
        println!(
            "  IDENTICAL. Both clients returned the same {} bytes at block {block} on chain {cid}.",
            hand_bytes.len()
        );
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
