# Task 16.1: reproduction audit

Run 2026-08-16 19:16:33 UTC. Verdict: **PASS**

9 of 9 gates passed. The chain holds 115 claims.

## What was re-run

| gate | time | result |
|---|---|---|
| `cargo test --workspace` | 59s | PASS |
| `forge test (contracts)` | 45s | PASS |
| `14.1 differential proof` | 30s | PASS |
| `14.2 vault invariants` | 89s | PASS |
| `14.6 learning effect` | 204s | PASS |
| `15.1 adversarial fee/vault` | 53s | PASS |
| `15.2 protocol version` | 52s | PASS |
| `14.7 phase 14 audit` | 50s | PASS |
| `chain inventory` | 1s | PASS |

## What was NOT re-run, and why

This is the number a reader should be suspicious of, so it is stated before anything else.

1. **Gates that spend gas.** The user funded this deployment with 0.005 OKB and the whole
   mainnet launch cost 0.000203652 of it. Re-running the mainnet and submission paths would
   spend their money to re-prove something the chain already records permanently. **16.3
   re-verifies those FROM CHAIN instead**, which is the stronger check: it reads what actually
   happened rather than doing it again and hoping it matches.
2. **Gates needing the Browser pane.** E11: with the pane closed, `requestAnimationFrame` and
   `setTimeout` callbacks do not run, so a headless shell cannot drive them. These are
   `scripts/dashboard_audit.js` and `scripts/failure_paths_audit.js`, named with their real
   reproduce path in the chain rather than dropped.

## Defects this audit found in the chain itself

The inventory pass runs BEFORE any re-execution, because a row citing a file that does not
exist is a defect a re-run would never surface: the runner would report a failure
indistinguishable from a flaky test.

It found three, all now repaired by `scripts/182-chain-repairs.py`:

1. **`C-710` appeared twice.** The second row was a rewrite of the first, so any reference to
   `[C-710]` was ambiguous. The superseded row is DELETED, taking the chain from 116 to 115.
2. **`C-906` cited `bash scripts/137-dashboard-audit.sh`, which never existed.** The real
   artefact is `scripts/dashboard_audit.js`, named inside the evidence file itself.
3. **`C-907` cited `bash scripts/138-failure-paths.sh`** with the same problem.

**2 and 3 are citation errors, not unreproducible claims, and the difference decides the
remedy.** 16.2 says a claim that does not reproduce is cut rather than footnoted. Cutting these
would have deleted real work with real evidence because a row pointed at the wrong filename.
The repair script checks the JS files exist FIRST and refuses to repair, requiring a cut,
if they do not.

## Reproduce

```
bash scripts/183-reproduce.sh
```
