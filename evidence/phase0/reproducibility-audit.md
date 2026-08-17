# Phase 1 reproducibility audit

Task 1.19. Run 2026-08-12 01:41:01 UTC

Method: delete the evidence file, run the command, check the file came back with content.
A command that cannot regenerate its own evidence is not a smoke test, it is a memory.

| tool | evidence file | command | deleted | regenerated | bytes |
|---|---|---|---|---|---|
| halmos | evidence/phase0/halmos.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/45c-halmos-upgrade.sh` | yes | **yes** | 1857 |
| hevm | evidence/phase0/hevm.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/47d-hevm-argotorg.sh` | yes | **yes** | 1756 |
| scribble | evidence/phase0/scribble.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/48-scribble-smoke.sh` | yes | **yes** | 2166 |
| act (substituted) | evidence/phase0/act.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/56-act-install.sh` | yes | **yes** | 3989 |
| codebase-memory | evidence/phase0/codebase-memory-mcp.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/58-codebase-memory-mcp.sh` | yes | **yes** | 6239 |
| paperscraper | evidence/phase0/paperscraper.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/51-paperscraper-smoke.sh` | yes | **yes** | 2263 |
| river | evidence/phase0/river.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/55-river-smoke.sh` | yes | **yes** | 1034 |
| support tools | evidence/phase0/support-tools.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/62-support-tools.sh` | yes | **yes** | 2896 |
| ui study audit | evidence/hypeterminal/citation-audit.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/74-verify-ui-study.sh` | yes | **yes** | 1344 |
| journal scale | evidence/phase4/journal-scale-audit.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/77-journal-scale-audit.sh` | yes | **yes** | 1445 |
| claim inventory | evidence/phase2/claim-inventory.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/63-claim-inventory.sh` | yes | **yes** | 4398 |
| graph query log | evidence/phase2/graph-query-log.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/64-graph-query-log.sh` | yes | **yes** | 10369 |
| chain + bytecode | evidence/phase2/deployment-bytecode.txt | `bash /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/scripts/67-verify-deployments.sh` | yes | **yes** | 1598 |

## Result

- regenerated: **13**
- failed to regenerate: **0**

Every evidence file above was DELETED and came back from its command.

## Excluded, with reasons

| tool | why not in the loop |
|---|---|
| alloy | its command recompiles alloy 2.3.0, 17m10s on this box. Re-run from a clean build earlier today, which is the same evidence this audit produces. |
| revm | recompiles revm 42, plus a contract build. Re-run from scratch earlier today, including three real failures fixed (gas cap, nonce sequence, pattern fields). |
| cargo-mutants | a full run is around 45 minutes and it ran three times today: 37 survivors, then 2, then 0. |
| gemini-grounding | re-running consumes the same free-tier quota whose exhaustion IS the finding. The failure is already precisely located: authenticated 404s and a model list prove key and transport, and the refusal is 429. |
| kontrol | substitution record, no command to re-run beyond the one that produced it. |
| gitleaks | full-history scan, and its findings live in the gitignored internal hygiene log rather than in a product evidence file. |
