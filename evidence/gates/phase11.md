# Phase 11 gate: mainnet preflight, zero spend

Closed 2026-08-16. Chain 196 read throughout. **Nothing deployed, nothing signed, nonce still 0.**

**CLOCK STOPS HERE (TASKS.md):** ready to spend, nothing spent, exact requirement known.

## Subtasks

| # | task | gate | verdict |
|---|---|---|---|
| 11.1 | chain 196 facts | `bash scripts/146-mainnet-facts.sh` | PASS, explorer loaded in a real browser |
| 11.2 | gas measured on testnet | `bash scripts/147-gas-inventory.sh` | PASS, receipts and live estimates, each labelled |
| 11.3 | exact OKB requirement | `bash scripts/148-mainnet-budget.sh` | PASS, 0.000473 OKB with a stated 3x margin |
| 11.4 | dry run, estimate only | `bash scripts/149-mainnet-dryrun.sh` | PASS, 0.0% against 11.3, zero spend proven |
| 11.5 | order and rollback | `bash scripts/151-deploy-plan.sh` | PASS, 17 steps, recovery for each |
| 11.6 | Exchange OS probe | `bash scripts/150d-call-discovered.sh` | PASS, absence established four ways |
| 11.7 | reverse engineer 196 | `bash scripts/150-reverse-engineer-196.sh` | PASS, 12 contracts characterised from bytecode |

Claims C-1100 through C-1106.

## The number

**0.000473160 OKB** budgeted, against a balance of **0.005 OKB** already funded by the user. Roughly
10x headroom.

```
deployment gas    5,521,463   MEASURED by cast estimate --create against chain 196
transaction gas   2,364,538   testnet receipts and live estimates
total             7,886,001
gas price        20,000,001 wei, read live
cost              0.000157720 OKB
x3 margin         0.000473160 OKB
```

The dry run and the budget agree to **0.0%**, because the dry run now READS the budget's output
rather than carrying a copy of it. The first version hardcoded the figure and kept comparing against
a number nothing produced any more.

## The per-byte model was 12.3% high, and was replaced rather than tolerated

Task 11.3 originally modelled deployment cost at 200 gas per byte plus 32,000 for the CREATE. The dry
run measured 5,521,463 against the model's 6,624,000. Task 11.4's PASS condition is agreement within
10%, and the honest way to close a 12.3% gap is to replace the estimate with the measurement, not to
widen the tolerance.

## Task 11.7: what the bytecode actually said

Twelve contracts fetched, hashed and saved to `evidence/phase11/bytecode/`.

**The finding that changed the method:** five OP Stack predeploys returned **byte-identical runtime
code**, keccak `0xfa8c9db6...977998`, 2059 bytes each. A message passer and a gas oracle cannot be
the same program, so the shared code is a proxy. Selector extraction on the proxy found nothing,
because a proxy has no dispatch table. Following the EIP-1967 slot, computed rather than pasted, gave
five distinct implementations.

Then selectors were extracted from the implementations and **identified by computing keccak256 of a
candidate signature locally**, so each match is arithmetic rather than a lookup to a service that
could be wrong or offline. 19 signatures identified on GasPriceOracle, 14 on L1Block.

Then every discovered function was CALLED, because a selector says a contract will answer and only a
return value says what it answers today.

| finding | label |
|---|---|
| X Layer runs the OP Stack | DEMONSTRATED, bytecode plus eth_call |
| Past Ecotone AND Fjord, GasPriceOracle v1.6.0 | DEMONSTRATED, `isEcotone()` and `isFjord()` both true |
| L2StandardBridge v1.13.0 with an L1 counterpart | DEMONSTRATED, eth_call |
| L1Block and GasPriceOracle are NOT stock implementations | DEMONSTRATED, EIP-1967 slot read |
| The L1 is Ethereum mainnet | **INFERRED**, and left that way |

## THE CORRECTION IT FORCED ON THIS PROJECT'S OWN NOTES

`CLAUDE.md` asserted "OP Stack Bedrock execution, **AggLayer settlement**, ~1.0s blocks".

The AggLayer half is **not visible in the bytecode at all**. What chain 196 exposes is a standard OP
Stack bridge stack. Three readings are possible and the evidence does not separate them: AggLayer
runs alongside and is invisible from L2, the migration has not happened on this chain, or the note
was taken from an announcement and is stale.

CLAUDE.md now records it as INFERRED and unverified, and the README must not state it as fact.

**The instruction for this task was that whitepaper and blog claims are hypotheses to verify onchain,
never ground truth. The first claim that failed that test was one of our own.**

## Task 11.6: Exchange OS, absence established four ways

1. **Documented surface**: okx.com returns 000, DNS non-resolution, consistent with E9.
2. **Working explorers**: oklink and xlayerscan both resolve; neither exposes an Exchange OS address.
3. **The chain itself**, the strongest attempt and the one depending on no website: 7 candidate
   addresses hold code, 5 are OP Stack system contracts, 2 are WOKB and Multicall3, and **0 are
   exchange primitives**.
4. **A real browser render**: task 11.1 loaded oklink in the pane and recorded its title.

**Finding: Exchange OS has no usable developer surface reachable from here on mainnet today.** The
SELF-DEPLOYED STAND-IN labels stay exactly as they are, and Exchange OS remains an INFERRED migration
target rather than a claimed integration.

## Zero spend, proven by the chain

```
nonce before   0
nonce after    0
balance before 5000000000000000 wei
balance after  5000000000000000 wei
```

No `--keystore` or `--password` appears anywhere in the dry-run script. That absence is the
guarantee, not the comment.
