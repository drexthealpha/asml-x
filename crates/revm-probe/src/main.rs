//! Task 1.13: deploy RiskGuard into revm's in-memory EVM, breach the per-market cap, and print
//! the revert data. Compared outside this program against the selector derived from the Solidity
//! source and against the revert data the live deployed contract returns.
//!
//! Nothing here touches the network. That is the point: this is what a pre-flight check would
//! run before paying gas.

use std::env;
use std::fs;

use revm::context::{Context, TxEnv};
use revm::context_interface::result::{ExecutionResult, Output};
use revm::database::CacheDB;
use revm::database_interface::EmptyDB;
use revm::primitives::{hex, Address, Bytes, TxKind, U256};
use revm::{ExecuteCommitEvm, MainBuilder, MainContext};

const AGENT: Address = Address::new([0x11; 20]);

fn selector(sig: &str) -> [u8; 4] {
    chain_client::selector(sig)
}

/// abi-encode a call: selector plus 32-byte words, which is all this probe needs.
fn call(sig: &str, words: &[[u8; 32]]) -> Bytes {
    let mut out = selector(sig).to_vec();
    for w in words {
        out.extend_from_slice(w);
    }
    Bytes::from(out)
}

fn word_u256(v: U256) -> [u8; 32] {
    v.to_be_bytes()
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let artifact = env::var("GUARD_ARTIFACT")?;
    let market_hex = env::var("MARKET_ID")?;

    // Creation bytecode from the SAME compiled artifact the deployment used.
    let json: serde_json::Value = serde_json::from_str(&fs::read_to_string(&artifact)?)?;
    let object = json["bytecode"]["object"]
        .as_str()
        .ok_or("no bytecode.object in the artifact")?;
    let mut init = hex::decode(object.trim_start_matches("0x"))?;

    // Constructor takes maxGross. 1000e18, matching the deployed configuration.
    let max_gross = U256::from(1_000u64) * U256::from(10u64).pow(U256::from(18u64));
    init.extend_from_slice(&word_u256(max_gross));

    let ctx = Context::mainnet().with_db(CacheDB::<EmptyDB>::default());
    let mut evm = ctx.build_mainnet();

    let created = evm.transact_commit(
        TxEnv::builder()
            .caller(AGENT)
            .kind(TxKind::Create)
            .data(Bytes::from(init))
            // 16_000_000, not 30_000_000. revm 42 enforces a per-transaction gas CAP of 16,777,216
            // (2^24) and rejects anything above it with TxGasLimitGreaterThanCap. That is EIP-7825
            // behaviour, and it is a real difference from the 210,000,000 block gas limit this
            // chain advertises: a simulator that allowed a 30M-gas transaction would be predicting
            // execution the protocol now refuses.
            .gas_limit(16_000_000)
            .build()
            .unwrap(),
    )?;
    let ExecutionResult::Success {
        output: Output::Create(_, Some(guard)),
        ..
    } = created
    else {
        println!("    DEPLOY FAILED in revm: {created:#?}");
        std::process::exit(1);
    };
    println!("    deployed into revm at {guard}");

    let market = {
        let raw = hex::decode(market_hex.trim_start_matches("0x"))?;
        let mut w = [0u8; 32];
        w.copy_from_slice(&raw[..32]);
        w
    };

    // The deployer is owner; AGENT is also the caller here, so appoint it and set the cap.
    let cap = U256::from(500u64) * U256::from(10u64).pow(U256::from(18u64));
    // The nonce has to be tracked by hand. `transact_commit` COMMITS state, including the caller's
    // nonce, and TxEnv defaults to nonce 0, so the second transaction fails with
    // NonceTooLow { tx: 0, state: 1 }. The deploy above consumed nonce 0, so calls start at 1.
    // Worth stating rather than patching silently: this is the difference between a simulator that
    // executes one transaction and one that executes a SEQUENCE, and a pre-flight for a multi-leg
    // batch is a sequence.
    let mut nonce: u64 = 1;
    let mut send =
        |sig: &str, words: &[[u8; 32]]| -> Result<ExecutionResult, Box<dyn std::error::Error>> {
            let r = evm.transact_commit(
                TxEnv::builder()
                    .caller(AGENT)
                    .kind(TxKind::Call(guard))
                    .data(call(sig, words))
                    .gas_limit(5_000_000)
                    .nonce(nonce)
                    .build()
                    .unwrap(),
            )?;
            nonce += 1;
            Ok(r)
        };

    let mut agent_word = [0u8; 32];
    agent_word[12..].copy_from_slice(AGENT.as_slice());
    let mut true_word = [0u8; 32];
    true_word[31] = 1;

    let r = send("setAgent(address,bool)", &[agent_word, true_word])?;
    println!(
        "    setAgent: {}",
        if r.is_success() { "ok" } else { "FAILED" }
    );
    let r = send("setMarketCap(bytes32,uint256)", &[market, word_u256(cap)])?;
    println!(
        "    setMarketCap(500e18): {}",
        if r.is_success() { "ok" } else { "FAILED" }
    );

    // Under the cap must succeed, so the refusal below is attributable to the CAP and not to a
    // misconfigured probe. Without this, a revert for any other reason would look like a pass.
    let under = U256::from(8u64) * U256::from(10u64).pow(U256::from(18u64));
    let r = send("addExposure(bytes32,uint256)", &[market, word_u256(under)])?;
    println!(
        "    addExposure(8e18) under the cap: {}",
        if r.is_success() { "ok" } else { "FAILED" }
    );
    if !r.is_success() {
        println!(
            "    probe misconfigured: a lawful add was refused, so the breach below proves nothing"
        );
        std::process::exit(1);
    }

    // Now breach it: 600e18 against the 500e18 cap, the same numbers as the live spine run.
    let over = U256::from(600u64) * U256::from(10u64).pow(U256::from(18u64));
    let r = send("addExposure(bytes32,uint256)", &[market, word_u256(over)])?;
    match r {
        // revm 42's Revert variant has NO `gas_used` field: the compiler's suggestion listed
        // `gas` and `logs`, and a second attempt keeping `gas_used` failed with E0026 naming it
        // explicitly. Bind only `output`, which is the field this probe is actually about.
        ExecutionResult::Revert { output, .. } => {
            println!("    addExposure(600e18) REVERTED");
            println!("    revert data: 0x{}", hex::encode(&output));
            println!(
                "    revert selector: 0x{}",
                hex::encode(&output[..4.min(output.len())])
            );
            // Decode the error's three fields to show the numbers are the real ones.
            if output.len() >= 4 + 96 {
                let attempted = U256::from_be_slice(&output[36..68]);
                let cap_seen = U256::from_be_slice(&output[68..100]);
                println!("    decoded attempted: {attempted}");
                println!("    decoded cap:       {cap_seen}");
            }
            Ok(())
        }
        other => {
            println!("    EXPECTED A REVERT, got {other:#?}");
            std::process::exit(1);
        }
    }
}
