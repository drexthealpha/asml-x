# Onchain gates in CI, against a local chain

Run 2026-08-17 19:50:25 UTC. Verdict: **PASS**

Chain id `1952` at `http://127.0.0.1:8545`, deployer
`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`, which is anvil's publicly known account 0 and funds nothing anywhere.

| stage | time | result |
|---|---|---|
| `deploy venue and guard` | 19s | PASS |
| `deploy the vault` | 4s | PASS |
| `seed an executable book` | 2s | PASS |
| `agent decides and acts` | 14s | PASS |
| `fund a depositor` | 5s | PASS |

## Why this is not a skipped gate

These deploy real contracts, submit real transactions and settle real trades against a real
EVM. What they do NOT do is prove anything about X Layer specifically: a fresh anvil chain has
no live order flow, no other participants and none of X Layer's OP Stack predeploys. The
mainnet claims rest on what chain 196 records, verified by
`scripts/184-mainnet-reverify.sh`, not on this.

No real key is involved. The alternative considered and rejected was putting the deployer
keystore in CI secrets, which would place a key holding real OKB one compromised action away
from being drained.

## Reproduce

```
bash scripts/196-ci-anvil-up.sh
bash scripts/197-ci-onchain-gates.sh
```
