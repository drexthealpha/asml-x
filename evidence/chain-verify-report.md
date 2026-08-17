# Chain verification report

Run 2026-08-10 19:36:26 UTC. dry=1

| id | evidence exists | command | result |
|---|---|---|---|
| C-100 | yes | `bash scripts/39-repo-hygiene-audit.sh` | dry, not run |
| C-103 | yes | `bash scripts/42-assert-claude-md.sh` | dry, not run |
| C-104 | yes | `bash scripts/40-install-gitleaks.sh` | dry, not run |
| C-105 | **MISSING** | `git log --oneline --all` | dry, not run |

## Summary

- rows: 4
- commands passed: 0
- commands failed: 0
- evidence artifacts missing: 1
- skipped (dry or no command): 4
