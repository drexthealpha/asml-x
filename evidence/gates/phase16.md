# Phase 16 gate report: full reproduction audit, including mainnet

Run 2026-08-16 19:49:36 UTC. Verdict: **PASS**

The chain holds 115 claims. Inventory clean: no malformed rows, no duplicate ids, no claim
without a command, no missing evidence file, no missing script.

## 16.1 reproduction

9 of 9 gates re-run and passing, including the full Rust workspace and 113 contract tests.
What was NOT re-run is stated in the report before anything else: gates that spend gas, because
re-running them would spend the user's OKB to re-prove what the chain already records, and
gates needing the Browser pane, which E11 makes impossible to drive headless.

## 16.2 repairs, three defects the audit found in the chain itself

1. `C-710` appeared **twice**, making any `[C-710]` reference ambiguous. Superseded row
   DELETED, 116 rows down to 115.
2. `C-906` cited `scripts/137-dashboard-audit.sh`, which never existed.
3. `C-907` cited `scripts/138-failure-paths.sh`, same problem.

2 and 3 are CITATION errors, not unreproducible claims, and the distinction decides the remedy:
the real artefacts (`scripts/dashboard_audit.js`, `scripts/failure_paths_audit.js`) exist and
are named inside the evidence files themselves. Cutting them would have deleted real work
because a row pointed at the wrong filename. The repair script checks those files exist FIRST
and refuses to repair, forcing a cut, if they do not.

## 16.3 mainnet, re-verified from chain 196

7 transactions each checked against **what its document CLAIMS**, not against success: 6
confirmed and 1 correctly REVERTED, that being the proof the risk guard refuses an over-cap
trade with real money at stake. An earlier version of this gate expected success everywhere and
failed on exactly that transaction, which would have inverted the meaning of Phase 12's most
important negative result.

7 contracts carry real bytecode. Live state: `feeBps` 50, `chargeCount` 1 so a fee was
actually charged on mainnet, treasury `0x...0fee0196` DISTINCT from the deployer, vault
solvent, `totalDeposits` 0 because the user's deposit was fully withdrawn.

Two hashes in the documents turned out not to be transactions at all: they are quoted REVERT
DATA, and a 4-byte selector plus a 32-byte market id is exactly 64 hex characters. The first
version used `cast receipt`, which BLOCKS waiting for confirmation, and hung indefinitely
waiting for a transaction that will never exist.

## 16.4 fake-win register

33 fake wins named in TASKS.md, **33 with a claim covering their subtask, 0 without**.

The register reports COVERAGE and prints each claim's text. It deliberately does not score
whether a refusal is convincing: a script asserting that thirty traps were avoided, written by
the same process that might have fallen into them, would be this task's own fake win.

## Reproduce

```
python3 scripts/181-repro-inventory.py
bash scripts/183-reproduce.sh
bash scripts/184-mainnet-reverify.sh
python3 scripts/185-fake-win-register.py
```
