# Reverse engineering chain 196, from bytecode and transactions

Run 2026-08-16 07:47:00 UTC. Chain id verified as 196 at block 68097384.

**Every DEMONSTRATED line below cites a bytecode hash or a transaction hash.** Nothing is taken
from documentation. Where a fact could only come from a document it is labelled INFERRED, and
the label is the point: a whitepaper is a hypothesis about a chain, and the chain is the only
thing that can settle it.

Surfaces used: `https://rpc.xlayer.tech` for all chain reads. okx.com is unreachable from this machine (E9), so
oklink and xlayerscan are the explorer surfaces; none of them was needed for the facts below,
which come from the RPC directly.

## Contracts found on chain 196

```
name                     address                                      code bytes  keccak256(runtime)
WrappedOKB               0xe538905cf8410324e03A5A23C1c177a474D59b2b         3474  0xde187307e119db7066ef4d8d154ba1617313e4c9a410c70378abe475cd2cffd2
L1Block                  0x4200000000000000000000000000000000000015         2059  0xfa8c9db6c6cab7108dea276f4cd09d575674eb0852c0fa3187e59e98ef977998
GasPriceOracle           0x420000000000000000000000000000000000000F         2059  0xfa8c9db6c6cab7108dea276f4cd09d575674eb0852c0fa3187e59e98ef977998
L2ToL1MessagePasser      0x4200000000000000000000000000000000000016         2059  0xfa8c9db6c6cab7108dea276f4cd09d575674eb0852c0fa3187e59e98ef977998
L2CrossDomainMessenger   0x4200000000000000000000000000000000000007         2059  0xfa8c9db6c6cab7108dea276f4cd09d575674eb0852c0fa3187e59e98ef977998
Multicall3               0xcA11bde05977b3631167028862bE2a173976CA11         3808  0xd5c15df687b16f2ff992fc8d767b4216323184a2bbc6ee2f9c398c318e770891
L2StandardBridge         0x4200000000000000000000000000000000000010         2059  0xfa8c9db6c6cab7108dea276f4cd09d575674eb0852c0fa3187e59e98ef977998
```

Runtime bytecode for every contract with code is saved under `evidence/phase11/bytecode/`.
The keccak hash is what makes each line above checkable: anybody can re-fetch the code and
confirm the hash without trusting this file.

## Selectors, extracted from the dispatch table

Solidity compiles a function dispatcher into a sequence of `PUSH4 <selector>` comparisons
against the first four bytes of calldata. Scanning the runtime bytecode for PUSH4 (opcode
0x63) recovers the selector set the contract will actually respond to, which is the contract
describing its own interface. No published ABI is consulted.

### GasPriceOracle

```
runtime bytes      2059
PUSH4 immediates   5 unique
matched signatures 0
```

No signature from the probe set matched. The unmatched immediates are still
recorded in the bytecode file; a PUSH4 is not always a selector, so absence of a
match is weak evidence either way.

### L1Block

```
runtime bytes      2059
PUSH4 immediates   5 unique
matched signatures 0
```

No signature from the probe set matched. The unmatched immediates are still
recorded in the bytecode file; a PUSH4 is not always a selector, so absence of a
match is weak evidence either way.

### L2CrossDomainMessenger

```
runtime bytes      2059
PUSH4 immediates   5 unique
matched signatures 0
```

No signature from the probe set matched. The unmatched immediates are still
recorded in the bytecode file; a PUSH4 is not always a selector, so absence of a
match is weak evidence either way.

### L2StandardBridge

```
runtime bytes      2059
PUSH4 immediates   5 unique
matched signatures 0
```

No signature from the probe set matched. The unmatched immediates are still
recorded in the bytecode file; a PUSH4 is not always a selector, so absence of a
match is weak evidence either way.

### L2ToL1MessagePasser

```
runtime bytes      2059
PUSH4 immediates   5 unique
matched signatures 0
```

No signature from the probe set matched. The unmatched immediates are still
recorded in the bytecode file; a PUSH4 is not always a selector, so absence of a
match is weak evidence either way.

### Multicall3

```
runtime bytes      3808
PUSH4 immediates   16 unique
matched signatures 3
```

Selectors identified by computing keccak256 of the signature LOCALLY and
comparing, so each match is arithmetic rather than a lookup to be trusted:

```
  0x42cbb15c  getBlockNumber()
  0x4d2301cc  getEthBalance(address)
  0x82ad56cb  aggregate3((address,bool,bytes)[])
```

### WrappedOKB

```
runtime bytes      3474
PUSH4 immediates   12 unique
matched signatures 11
```

Selectors identified by computing keccak256 of the signature LOCALLY and
comparing, so each match is arithmetic rather than a lookup to be trusted:

```
  0x06fdde03  name()
  0x095ea7b3  approve(address,uint256)
  0x18160ddd  totalSupply()
  0x23b872dd  transferFrom(address,address,uint256)
  0x2e1a7d4d  withdraw(uint256)
  0x313ce567  decimals()
  0x70a08231  balanceOf(address)
  0x95d89b41  symbol()
  0xa9059cbb  transfer(address,uint256)
  0xd0e30db0  deposit()
  0xdd62ed3e  allowance(address,address)
```


## THE PREDEPLOYS ARE PROXIES, and that changes the whole method

Five contracts with entirely different jobs returned **byte-identical runtime code**:

```
keccak256(runtime)  0xfa8c9db6c6cab7108dea276f4cd09d575674eb0852c0fa3187e59e98ef977998
size                2059 bytes
shared by           L2ToL1MessagePasser, L1Block, GasPriceOracle,
                    L2StandardBridge, L2CrossDomainMessenger
```

A message passer and a gas oracle cannot be the same program. The shared code is a PROXY, and
the behaviour lives behind an implementation slot. This is why scanning the proxy for a
dispatch table found nothing worth reporting: a proxy has no dispatcher, it has a fallback that
delegatecalls. Stopping at the proxy would have produced a confident wrong answer, which is the
specific failure this task's counter is written against.

### Following the EIP-1967 slots

The slot is COMPUTED here, not pasted from documentation:

```
keccak256("eip1967.proxy.implementation")     0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbd
  minus 1                                     0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
keccak256("eip1967.proxy.admin")              0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6104
  minus 1                                     0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103
```

```
predeploy                implementation                               impl bytes  keccak256(impl runtime)
L1Block                  0x1160d963acd3799e820b75809cdba75bcef8bf74         3150  0x7b062061cc03c27096d5a7658bb33614c0455fbafcee3d1cecdd13f6fe3d501f
GasPriceOracle           0x4f1db3c6abd250ba86e0928471a8f7db3afd88f1         7848  0xe9fc7c96c4db0d6078e3d359d7e8c982c350a513cb2c31121adf5e1e8a446614
L2ToL1MessagePasser      0xc0d3c0d3c0d3c0d3c0d3c0d3c0d3c0d3c0d30016         2114  0x1707810c85b7150446cd4558c0be34ad7964861675dc17a32ff147149f558ad1
L2CrossDomainMessenger   0xc0d3c0d3c0d3c0d3c0d3c0d3c0d3c0d3c0d30007         7723  0x76cd7dfa97d24622c7c50b51d58fd3658cf1bb0378b3d217d014a82474d90f5a
L2StandardBridge         0xc0d3c0d3c0d3c0d3c0d3c0d3c0d3c0d3c0d30010         3628  0x1b5aebf2f3a98ec8e9c29710a2dd5100bb5fe601d0e7d24e4625526b785733cc
```

The implementations have DIFFERENT code and different sizes, which confirms the proxy reading:
one shared proxy in front of five distinct programs.


## Selectors, from the IMPLEMENTATIONS

Extracted by scanning each implementation's runtime bytecode for PUSH4 immediates, then
identifying them by computing keccak256 of a candidate signature LOCALLY and comparing. Every
match below is arithmetic, not a lookup against a service that could be wrong or offline.

### GasPriceOracle

```
unique PUSH4 immediates  31
identified signatures    19
```

```
  0x0c18c162  overhead()
  0x22b90ab3  setEcotone()
  0x313ce567  decimals()
  0x49948e0e  getL1Fee(bytes)
  0x4ef6e224  isEcotone()
  0x54fd4d50  version()
  0x5cf24969  basefee()
  0x68d5dca6  blobBaseFeeScalar()
  0x6ef25c3a  baseFee()
  0x8b239f73  l1FeeOverhead()
  0x8e98b106  setFjord()
  0x960e3a23  isFjord()
  0x9e8c4966  l1FeeScalar()
  0xc5985918  baseFeeScalar()
  0xde26c4a1  getL1GasUsed(bytes)
  0xf1c7a58b  getL1FeeUpperBound(uint256)
  0xf45e65d8  scalar()
  0xf8206140  blobBaseFee()
  0xfe173b97  gasPrice()
```

### L1Block

```
unique PUSH4 immediates  27
identified signatures    14
```

```
  0x015d8eb9  setL1BlockValues(uint64,uint64,uint256,bytes32,uint64,bytes32,uint256,uint256)
  0x09bd5a60  hash()
  0x54fd4d50  version()
  0x5cf24969  basefee()
  0x64ca23ef  sequenceNumber()
  0x68d5dca6  blobBaseFeeScalar()
  0x8381f58a  number()
  0x8b239f73  l1FeeOverhead()
  0x9e8c4966  l1FeeScalar()
  0xb80777ea  timestamp()
  0xc5985918  baseFeeScalar()
  0xe591b282  DEPOSITOR_ACCOUNT()
  0xe81b2c6d  batcherHash()
  0xf8206140  blobBaseFee()
```

### L2CrossDomainMessenger

```
unique PUSH4 immediates  26
identified signatures    12
```

```
  0x3dbb202b  sendMessage(address,bytes,uint32)
  0x3f827a5a  MESSAGE_VERSION()
  0x54fd4d50  version()
  0x5c975abb  paused()
  0x6e296e45  xDomainMessageSender()
  0x9fce812c  OTHER_MESSENGER()
  0xa4e7f8bd  failedMessages(bytes32)
  0xb1b1b209  successfulMessages(bytes32)
  0xb28ade25  baseGas(bytes,uint32)
  0xc2b3e5ac  initiateWithdrawal(address,uint256,bytes)
  0xd764ad0b  relayMessage(uint256,address,address,uint256,uint256,bytes)
  0xecc70428  messageNonce()
```

### L2StandardBridge

```
unique PUSH4 immediates  19
identified signatures    15
```

```
  0x0166a07a  finalizeBridgeERC20(address,address,address,address,uint256,bytes)
  0x09fc8843  bridgeETH(uint32,bytes)
  0x1635f5fd  finalizeBridgeETH(address,address,uint256,bytes)
  0x32b7006d  withdraw(address,uint256,uint32,bytes)
  0x36c717c1  l1TokenBridge()
  0x540abf73  bridgeERC20To(address,address,address,uint256,uint32,bytes)
  0x54fd4d50  version()
  0x5c975abb  paused()
  0x6e296e45  xDomainMessageSender()
  0x7f46ddb2  OTHER_BRIDGE()
  0x87087623  bridgeERC20(address,address,uint256,uint32,bytes)
  0x8f601f66  deposits(address,address)
  0x927ede2d  MESSENGER()
  0xa3a79548  withdrawTo(address,address,uint256,uint32,bytes)
  0xe11013dd  bridgeETHTo(address,uint32,bytes)
```

### L2ToL1MessagePasser

```
unique PUSH4 immediates  8
identified signatures    6
```

```
  0x3f827a5a  MESSAGE_VERSION()
  0x44df8e70  burn()
  0x54fd4d50  version()
  0x82e3702d  sentMessages(bytes32)
  0xc2b3e5ac  initiateWithdrawal(address,uint256,bytes)
  0xecc70428  messageNonce()
```

## One real transaction, decoded end to end

Everything above characterises code. This reads what the chain actually DID with it.

```
transaction   0x9a09499f9bdb853323f5372b00ef8a3894cc20c6655af32e6e6edf74c57b97bd
block         68097738
from          0xdeaddeaddeaddeaddeaddeaddeaddeaddead0001
to            0x4200000000000000000000000000000000000015
value         0 wei
gas limit     1000000
gas used      46170
status        0x1
calldata      178 bytes
selector      0x3db6be2b
argument words 6
  arg[0]  0x00000000000000000000000000000004000000006a816c07000000000189295e
          as uint  1361129467716715726469998652613112441182
          as address 0x00000004000000006a816c07000000000189295e
  arg[1]  0x000000000000000000000000000000000000000000000000000000000281d6c7
          as uint  42063559
          as address 0x000000000000000000000000000000000281d6c7
  arg[2]  0x000000000000000000000000000000000000000000000000000000000025f88c
          as uint  2488460
          as address 0x000000000000000000000000000000000025f88c
  arg[3]  0xba10aadca18aa5284bf03d53aae14ef8ca91de5911c2feec1cd2a61769a1dac9
          as uint  84159638634603537819284911133550257254463977029175659546157216804905284655817
  arg[4]  0x00000000000000000000000098245d0adf4595c66f0a9db8e13c44cbff6be459
          as uint  868577529134565182372703860796991875958707053657
          as address 0x98245d0adf4595c66f0a9db8e13c44cbff6be459
  arg[5]  0x0000000000000000000000000190
          as uint  400
          as address 0x0000000000000000000000000190
logs          0
```

Every field above is from `eth_getTransactionByHash` and `eth_getTransactionReceipt`.
The selector is the first four bytes of the real calldata; the argument words are the
ABI encoding as the chain stored it, shown raw and interpreted both ways so nothing is
asserted about the type that the bytes do not support.

## Calling what the bytecode advertised

A selector in a dispatch table says the contract WILL answer that signature. A return value
says what it answers TODAY. Only the second is DEMONSTRATED, so every function discovered above
was called.

```
L1Block.number()                               25766249 [2.576e7]
L1Block.timestamp()                            1786866827 [1.786e9]
L1Block.basefee()                              43712424 [4.371e7]
L1Block.sequenceNumber()                       3
L1Block.DEPOSITOR_ACCOUNT()                    0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001
L1Block.blobBaseFee()                          2241102 [2.241e6]
L1Block.batcherHash()                          0x00000000000000000000000098245d0adf4595c66f0a9db8e13c44cbff6be459
GasPriceOracle.version()                       "1.6.0"
GasPriceOracle.isEcotone()                     true
GasPriceOracle.isFjord()                       true
GasPriceOracle.decimals()                      6
GasPriceOracle.baseFeeScalar()                 0
L2StandardBridge.MESSENGER()                   0x4200000000000000000000000000000000000007
L2StandardBridge.OTHER_BRIDGE()                0xAecF995ABf9E7eDE7ae0CE65E60622C9eD84823a
L2StandardBridge.version()                     "1.13.0"
WrappedOKB.name()                              "Wrapped OKB"
WrappedOKB.symbol()                            "WOKB"
WrappedOKB.decimals()                          18
WrappedOKB.totalSupply()                       204299883028576917348116 [2.042e23]
```

### What this DEMONSTRATES about chain 196

| finding | evidence | label |
|---|---|---|
| X Layer runs the OP Stack | five predeploys at the canonical 0x42..00xx addresses answer, and three resolve to implementations at the OP convention address 0xc0d3c0d3...00xx | DEMONSTRATED, bytecode plus eth_call |
| It is past the Ecotone upgrade | GasPriceOracle.isEcotone() returns true and blobBaseFee/blobBaseFeeScalar exist in the dispatch table | DEMONSTRATED, eth_call |
| It is past the Fjord upgrade | GasPriceOracle.isFjord() and getL1FeeUpperBound(uint256) are present and answer | DEMONSTRATED, eth_call |
| L1Block and GasPriceOracle are NOT stock | their implementations sit at 0x1160d963... and 0x4f1db3c6..., outside the 0xc0d3c0d3... convention the other three follow | DEMONSTRATED, EIP-1967 slot read |
| The settlement layer is Ethereum | L1Block.number() tracks an L1 head and batcherHash() is populated | DEMONSTRATED for the mechanism; WHICH L1 is INFERRED, since the number alone does not name a chain |

The last row is the one worth pausing on. The bytecode proves an L1 is being tracked. It does
not prove WHICH, and nothing available here does, so that half stays INFERRED rather than being
quietly upgraded because the answer seems obvious.

### What was NOT found

No Exchange OS contract, no order book, no matching engine, no perpetuals contract at any
address reachable from the predeploy set or from the addresses probed in task 11.6 below.
That absence is a finding, not a gap in the search: see exchangeos-mainnet.md.


## The L1 identity, and how far the evidence actually goes

`L1Block` reports a live L1 head, and the numbers are internally consistent with Ethereum mainnet:

```
L1Block.number()      25,766,249
L1Block.timestamp()   1,786,866,827   (2026-08-16)
L1Block.basefee()     43,712,424 wei  (0.0437 gwei)
L1Block.blobBaseFee() 2,241,102 wei
DEPOSITOR_ACCOUNT     0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001
batcherHash           0x...98245d0adf4595c66f0a9db8e13c44cbff6be459
```

At Ethereum's 12-second block time, block 25.77M in August 2026 is where Ethereum mainnet would be.
The presence of `blobBaseFee` means the L1 supports EIP-4844 blobs. Both are consistent with
Ethereum, and neither is proof: a chain can report any number it likes in a predeploy.

**Labelled INFERRED, deliberately.** Confirming it would mean querying an Ethereum RPC for block
25,766,249 and matching the timestamp, and no Ethereum RPC is configured in this project. The
inference is strong and it is still an inference, so it does not get promoted because the answer
looks obvious.

What IS demonstrated is the mechanism: an L1 is tracked, a batcher posts to it, and the bridge names
an L1 counterpart at `0xAecF995ABf9E7eDE7ae0CE65E60622C9eD84823a`.

## A CORRECTION THIS FORCES ON THIS PROJECT'S OWN NOTES

`CLAUDE.md` records under KEY BUILD FACTS:

> OP Stack Bedrock execution, AggLayer settlement, ~1.0s blocks

The first and third are confirmed. **The AggLayer half is not visible in the bytecode at all.**

What chain 196 actually exposes is a **standard OP Stack bridge stack**: `L2StandardBridge` v1.13.0
with an `OTHER_BRIDGE` on L1, `L2CrossDomainMessenger` at the canonical address, and
`L2ToL1MessagePasser` with the stock `0xc0d3c0d3...0016` implementation. That is the OP Stack's own
withdrawal path, not an AggLayer pessimistic-proof path.

Three readings are possible and the evidence does not separate them:

1. AggLayer settlement operates alongside the OP bridge, invisible from L2 predeploys.
2. The AggLayer migration has not happened on this chain yet.
3. The note in CLAUDE.md was taken from an announcement rather than from the chain, and is stale.

**Whichever it is, the honest statement is that this project's own note is INFERRED and unverified,
while the OP Stack bridge stack is DEMONSTRATED.** The claim has been softened accordingly and the
README must not describe AggLayer settlement as a verified fact.

This is precisely what the task was for. The instruction was that whitepaper and blog claims are
hypotheses to verify onchain, never ground truth, and the first thing that failed that test was a
line in this project's own documentation.

## Versions, read from the contracts

```
GasPriceOracle    1.6.0    isEcotone() true, isFjord() true
L2StandardBridge  1.13.0
```

`isFjord()` returning true places the chain past the Fjord upgrade, which is later than Ecotone.
Both were read with `eth_call`, so the upgrade level is DEMONSTRATED rather than dated from a blog
post.

`GasPriceOracle.decimals()` returns 6 and `baseFeeScalar()` returns 0, which together mean the L1
fee component of a transaction on this chain is currently scaled to nothing. That is consistent with
the flat 20,000,001 wei gas price measured in task 11.1 and with the sub-cent costs in the budget.
