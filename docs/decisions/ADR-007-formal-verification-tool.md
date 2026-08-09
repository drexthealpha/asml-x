# ADR-007: Halmos, not CertoraProver

Date 9 Aug 2026. Status ACCEPTED. Task 3.1.

## Context
The plan mandated CertoraProver for the risk and kill-switch logic. It is GPLv3
and documented as locally runnable, but the local route is a JVM build with a
Python venv and pinned solc versions, while the supported route is their cloud
service.

## Decision
Use Halmos for the symbolic proofs. R16 applied before getting stuck rather than
after: Halmos is a pip install, runs fully locally with no key, reads ordinary
Solidity so the proofs sit beside the Foundry tests, and targets exactly the class
of property ADR-006 needs.

## Evidence it is sufficient
Seven theorems over RiskGuard, each proven for ALL inputs in the declared ranges
rather than sampled: per-market cap over any two adds, gross cap across two
markets, killed blocks every add for any amount, only-owner revive over a symbolic
caller address, only-owner cap raise, gross always equals sum of parts across
add/add/reduce, and unconfigured markets failing closed for any market id.
Output: evidence/formal/halmos-riskguard.txt

## Proof that the proofs can fail
Injected violation: the per-market cap check loosened by one wei.
Prover caught it: **yes** (2 proof(s) failed under mutation,
0 after restore).
Output: evidence/formal/halmos-injected-violation.txt

## Cost, stated plainly
Certora's CVL is more expressive for multi-contract and parametric rules, and a
Certora report carries more weight with auditors. The theorems here are written as
pre and post conditions rather than in Halmos-specific idiom, so they translate if
a Certora run is wanted later. This substitution is disclosed in the README, not
glossed over.
