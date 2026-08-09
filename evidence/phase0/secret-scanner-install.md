# Tool install: secret scanner

Captured 2026-08-10 08:24:02 UTC.

| attempt | method | result |
|---|---|---|
| 1 | plain WSL curl to api.github.com | ok |
| 2 | DoH resolve + curl --resolve pin | ok |
| 3 | pip detect-secrets substitute | skipped |

OUTCOME: gitleaks available, version 8.30.1.
