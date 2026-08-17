# Task 12.3: an explicit risk refusal on mainnet

Run 2026-08-16 08:42:52 UTC.

**Chain id 196. Block 68100740.**

Both are stated because this task's named fake win is showing a testnet refusal and captioning
it mainnet. Every artifact below is from chain 196.

## 1. The onchain guard refuses, as a SUBMITTED transaction

The market cap is 500 aQUOTE. This asks the guard to record 900, which is over it.

```
RiskGuard        0x9D22e538a72a5d2c9A28D08c27999216A78343C9
market           0x6b96e18e311cbaf06645140e28c8699906effa36fd1095ee0b6abe99542f9377
maxPerMarket     500000000000000000000
current exposure 2850000000000000000
requested        900000000000000000000
```

### Simulated call, for the decoded custom error

```
Error: server returned an error response: error code 3: execution reverted, data: "0x3e2ed0286b96e18e311cbaf06645140e28c8699906effa36fd1095ee0b6abe99542f9377000000000000000000000000000000000000000000000030f18f8b7ee56d000000000000000000000000000000000000000000000000001b1ae4d6e2ef500000"
```

### The submitted transaction

```
tx      0x6a0237847f4d73794b56b3083f0603e91e831cfd3cf20281f8665ec63c83e48e
status  0x0      (0x0 means REVERTED, which is the pass for this task)
block   68100752    (mainnet)
```

https://www.oklink.com/x-layer/tx/0x6a0237847f4d73794b56b3083f0603e91e831cfd3cf20281f8665ec63c83e48e

A reverted transaction is still a permanent onchain record. Anybody can fetch this receipt and
see that the attempt was made on chain 196 and refused by the deployed guard.

## 2. The vault refuses a per-user limit breach, on mainnet

```
approve vault:     0x1
deposit 10, cap 1: 0x1
vault.maxNotional: 1000000000000000000
vault.balanceOf:   10000000000000000000

Asking the agent to trade 2 aQUOTE against the user's own 1 aQUOTE limit, with 10 on deposit.
There are ample funds. The only thing refusing it is the user's own limit.

Error: server returned an error response: error code 3: execution reverted, data: "0x38888fc70000000000000000000000000000000000000000000000001bc16d674ec800000000000000000000000000000000000000000000000000000de0b6b3a7640000"
```

## 3. The offchain engine refuses to construct RiskApproved

The same limit exists in the Rust risk engine, where a refusal is a type-level fact rather than
a revert: `RiskApproved<T>` has exactly one constructor and it is behind this check.

```
test tests::per_user_limits_refuse_an_order_the_system_would_allow ... ok
test tests::per_user_market_limit_is_checked_on_projected_exposure ... ok
test tests::prop_a_user_limit_can_never_widen_what_the_system_allows ... ok
test result: ok. 43 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.26s
test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

## Why three artifacts and not one

A revert proves the deployed bytecode refuses. A decoded custom error proves WHICH limit and by
how much. A failing type-level construction proves the refusal is not merely enforced at the
edge but is impossible to route around offchain. Any one of them alone would leave a gap that a
sceptical reader could reasonably point at.
