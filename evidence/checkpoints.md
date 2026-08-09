# Checkpoint ledger

R18 forbids git tags, so this file is the audit trail instead. One line per
checkpoint: name, UTC time, what was proven, evidence path.

| checkpoint | UTC | proven | evidence |
|---|---|---|---|
| CHECKPOINT-0 | 2026-08-09 07:01 | Chain 1952 live, wallet funded, first real deploy and tx landed with explorer links | evidence/first-tx.md |
| CHECKPOINT-1-RECON | 2026-08-09 07:01 | OP Stack determination from bytecode, chain activity scan, Exchange OS absence established from primary sources | docs/verified/chain-1952-reality.md |
| CHECKPOINT-2.1 | 2026-08-09 07:01 | Risk engine: 16 tests green, 14/14 mutations RED, forging RiskApproved fails to compile | evidence/mutation-risk-engine.md |
| CHECKPOINT-2.2 | 2026-08-09 07:44 | Venue stack deployed and wired on chain 1952, 15/15 contract mutations RED | docs/verified/deployments.md |
| CHECKPOINT-2.4-SPINE-GREEN | 2026-08-09 07:44 | Live multi-leg atomic batch, live cap refusal, live kill switch, live de-risk while killed | evidence/spine-run-01/README.md |
| CHECKPOINT-4-AI-LIVE | 2026-08-09 11:02 | Agent-driven decisions submitting real txs, 11-candidate scored search, unit-scale and taker-economics bugs fixed | evidence/gates/phase-4.md |
