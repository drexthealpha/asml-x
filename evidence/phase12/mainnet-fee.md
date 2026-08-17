# Task 12.4: a live fee event on mainnet

Run 2026-08-16 08:41:15 UTC. Chain id 196.

Decoded from `eth_getTransactionReceipt` on chain 196. Nothing is read from local state.

```
FeeCollector  0x7ff884C412a1A2c416e931C59889e5335C5EFa0D
transaction   0xb4785fbcbd2ba5f007b5735c63ee671aa178547da066bceb6ae0bef75bbcec6f
payer         0x7092050f3c4e72a2df8610ae2cc8c39dca3b7f52
market        0x6b96e18e311cbaf06645140e28c8699906effa36fd1095ee0b6abe99542f9377
token         0x12dcbe73416cdfe6de0681286c25ace81b4644c0
notional      2850000000000000000
feeAmount     14250000000000000
feeBps        50
arithmetic    2850000000000000000 * 50 / 10000 = 14250000000000000, matches: True
```

**1 FeeCharged event decoded from a mainnet receipt with a non-zero feeAmount.**

## Cross-checked against contract state

An event is a claim a contract makes about itself. A balance is what happened.

```
treasury                0x000000000000000000000000000000000fee0196
treasury aQUOTE balance 14250000000000000
fee.chargeCount()       1
```

The treasury is NOT the deployer, so this balance is fee revenue and nothing else. Task 7.6
found that with treasury == maker == deployer the two are indistinguishable.

Explorer: https://www.oklink.com/x-layer/tx/0xb4785fbcbd2ba5f007b5735c63ee671aa178547da066bceb6ae0bef75bbcec6f
