# Task 18.3: final security sweep

Run 2026-08-16 20:29:47 UTC. Verdict: **PASS**

## Why a scanner alone is not enough

gitleaks finds patterns it knows. It cannot tell you that key material sits in a file it never
scanned because the file is untracked, nor that a gitignored file is one `git add -f` from
being published. So this checks three separate things: what the scanner finds, **where the key
material actually lives on disk**, and what git would include if someone committed everything
right now.

## 1. gitleaks full history

**0 finding(s).**

Clean.

## 2. Key material is outside the repository

| check | result |
|---|---|
| keystore at `~/.asml-keys/asml-deployer` | yes |
| password at `~/.asml-keys/keystore.pass` | yes |
| key-shaped files anywhere inside the repo tree | **0** |

Both live outside the working tree entirely, so no `git add`, however forced, can reach them.
The deployer's PUBLIC address appears throughout by design and is not a secret.

## 3. Internal files are gitignored

3 of 3 checked. These carry build instructions, environment facts and session state, and
are not part of the submission.

## Reproduce

```
bash scripts/189-final-sweep.sh
```
