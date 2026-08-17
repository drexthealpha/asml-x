# Phase 9 gate: the zero-friction flow

Closed 2026-08-16. Chain 1952. Every gate below was run, not asserted.

**CLOCK STOPS HERE (TASKS.md): THIS IS THE FIRST POINT AT WHICH THIS IS A PRODUCT.** A person
connects, accepts defaults, deposits, activates, watches it decide, pauses, withdraws.

## Subtasks

| # | task | gate | verdict |
|---|---|---|---|
| 9.0 | browser wallet | **USER HANDLES** | OUTSTANDING, see below |
| 9.1 | wallet connection | `bash scripts/130-connect-flow.sh` | PASS, real address + chain, 3 failures recovered |
| 9.2 | landing surface | `bash scripts/131-landing-audit.sh` | PASS, primary action in viewport at both sizes |
| 9.3 | smart defaults | `bash scripts/132-defaults-audit.sh` | PASS, crate == screen == chain |
| 9.4 | three clicks | `bash scripts/133-click-count.sh` | PASS, exactly 3 from cold |
| 9.5 | exit always visible | `bash scripts/134-exit-controls-audit.sh` | PASS, 5 routes x 2 viewports |
| 9.6 | Run Full Demo | `bash scripts/135-demo-button.sh` | PASS, 10 of 10, slowest 17.6s |
| 9.7 | dashboard immediately | `bash scripts/137-dashboard-audit.sh` | PASS, 11ms against a 1000ms budget |
| 9.8 | recoverable failures | `bash scripts/138-failure-paths.sh` | PASS, 5 of 5, zero dead ends |
| 9.9 | fee disclosure | `bash scripts/139-fee-disclosure.sh` | PASS, UI followed a live 50 to 49 change |
| 9.10 | audit and frontend gate | `bash scripts/140-phase9-redteam.sh` | PASS at desktop, mobile clipping named |

## Task 9.0 is still outstanding

Install a browser wallet with chain 1952. Everything above was verified against a REAL key-backed
EIP-1193 provider (ADR-016): a real testnet key, `eth_chainId` answered by the live RPC, real
transactions in real blocks. Never a stub, because a stub IS task 9.1's named fake win.

What remains untested is the extension's confirmation popup and its exact error surface. The same
gates re-run unchanged against an extension; if any fails there, the difference is in the extension
and worth finding.

## What a person can now do

Connect, see the shipped limits with what each protects against, press one button to deposit and
activate in three interactions, watch the agent decide, pause it from any screen, and withdraw in
full while paused. Or press Run Full Demo and watch a complete cycle without connecting anything.

## FAKE WIN REGISTER

| named fake win | fired? |
|---|---|
| 9.1 a Connect button that sets local state without touching a provider | No. Address from `eth_requestAccounts`, chain from `eth_chainId`, both read out of DOM data attributes the component wrote from provider responses. |
| 9.2 a beautiful landing page that hides the product behind a second click | No. The personal view is the FIRST tab and the default, so the click count starts at zero. |
| 9.3 defaults displayed that differ from what is written onchain | No, and a third source was added: `limits.json` is WRITTEN BY the Rust crate, so the screen cannot drift from the engine. |
| 9.4 counting only in-app clicks | **YES, TWICE.** See below. |
| 9.5 controls present but below the fold | No. Bounding rect plus an `elementFromPoint` hit test on all 5 routes at both viewports. |
| 9.6 a demo that replays a recorded journal | No. Journal length before and after is shown on screen and asserted per run; block numbers all distinct. |
| 9.7 showing zeros while loading | No. Every field renders a word while loading; the activation button is a tri-state where `null` disables it. |
| 9.8 a generic "something went wrong" toast | **YES.** A raw hex dump is the same failure in a different costume. |
| 9.9 a hardcoded percentage | No. Proved by changing the rate on chain and watching the UI follow. |
| 9.10 uncited frontend files | No. 0 of 14 components uncited. |

## The two that fired, in full

**9.4 measured ONE click, twice, and both numbers were real and both claims would have been false.**
First during 9.3, because the account held a 1e24 allowance from Phase 7. Then again after
redeploying for permit, because `112c-vault-deploy.sh` approves the vault at deploy time. One click
is true of a warm account and false of every first visitor. `make-cold.sh` now zeroes allowance and
balance, and the gate asserts the cold state on chain before the browser opens. The real cold path
was FOUR interactions, and ADR-017 added ERC-2612 permit to make it three: click, sign, confirm.

**9.8 rendered raw reverts.** Asking to withdraw more than the balance produced
`0xcf47918100000000...` on screen. Every fact was present and none of it legible.
`ui-v2/src/lib/revert.ts` decodes seven custom errors into a cause and an action; the same revert now
reads "You asked to withdraw 1000000.0000 tQUOTE but only 50.0000 is available right now. Withdraw
50.0000 tQUOTE or less."

## Defects found that no task asked for

1. **A Phase 7 regression that broke every SELL.** Task 7.6 removed the per-batch `approve` legs to
   save ~24k gas and granted only tQUOTE at deploy. The comment saying "both allowances are set" was
   left behind after the code that made it true was deleted. Hidden until the first sell, which
   reverted with `LegFailed(1, venue, ...)`. Both tokens now granted, and the seeder re-asserts them.
2. **Two components polling the chain independently hid the exit control.** 14 `eth_call`s per five
   seconds got the public RPC to refuse connections; both components swallow read errors, so the exit
   bar silently never appeared on a page that looked healthy. One shared poll now.
3. **Silent staleness.** During an outage the balance kept displaying a figure nobody was confirming.
   The controls stay, and now a warning says the figure is not current.
4. **Route changes refetched build artifacts.** Dashboard panels appeared at 1627ms because every
   remount refetched the manifest. Cached at module level; now 980ms, first data at 11ms.
5. **Three more wrong hand-written selectors** in the revert decoder, caught by `cast sig`. That is
   eight wrong selectors across this build. A wrong one never throws: it returns `0x` or fails to
   match, and renders as a confident zero or a raw hex fallback.

## Known defect, scoped rather than fixed

The four Phase 4 views clip at 390x844, measured by the project's own `measure-overflow.js`. ADR-018
records the decision and, more importantly, records that an earlier Phase 9 audit reported a much
larger mobile catastrophe which was entirely its own false positives. The remaining failure is real
and small. The product must not be described as responsive or mobile-ready.

## A note on instrument error

Three gates in this phase reported something false. Two UNDER-reported and were fixed by adding
checks. One OVER-reported, escalated a false emergency, and extracted a scope decision from the user
on numbers my own code invented. The rule that came out of it: **inspect a sample of individual
findings before reporting a count as a defect.** A number from an unchecked instrument is not
evidence, including an instrument I wrote.
