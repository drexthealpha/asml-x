# Phase 18 gate report: video, sweep, submit

Run 2026-08-16 20:39:01 UTC.

## 18.1 demo script — DONE

[docs/DEMO-SCRIPT.md](../../docs/DEMO-SCRIPT.md), three minutes, timed to the spec's shape:
land, connect, defaults, deposit, activate, decision and fee event, pause, withdraw, Terminal.

It carries a **What must NOT be said** list: no USD figure, no performance language, nothing
calling AggLayer verified, nothing claiming Exchange OS integration, and no mention of the
venue without "self-deployed stand-in" nearby.

**The refusal is scheduled on camera at 1:45, deliberately.** A demo edited to remove a refusal
advertises the opposite of what this project claims.

Every beat was verified against the live built page: 9 of 10 confirmed, the tenth being the fee
disclosure which only renders after Connect. See [demo-beats.md](../phase18/demo-beats.md).

## 18.3 final sweep — DONE, PASS

**0 gitleaks findings** across the full history. The keystore and its password both live at
`~/.asml-keys/`, **outside the working tree entirely**, so no `git add` however forced can
reach them. **0 key-shaped files anywhere inside the repo tree.** CLAUDE.md, RESUME.md and
TASKS.md all confirmed gitignored.

A scanner alone would not have been enough: gitleaks finds patterns it knows, and cannot tell
you that key material sits in a file it never scanned. So this checked three things separately.

## 18.2 record the video — NEEDS THE USER

Everything that can be prepared is prepared: the script is written and timed, the pre-recording
commands are listed, and the page has been verified to contain what the script points at.

**Producing the actual screen recording requires a human at a screen recorder**, and a wallet
extension, which is the same user-handled dependency as task 9.0. This is stated as an
outstanding item rather than marked complete.

## 18.4 submission — USER HANDLES, unchanged

The dedicated X account, the submission post mentioning @XLayerOfficial, the Google Form, and
**every git commit, push and tag**. No git operation has been performed by this build.

## Reproduce

```
bash scripts/189-final-sweep.sh
```
