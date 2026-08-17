# Task 9.7: personal dashboard with real data immediately

Run 2026-08-16. Measured in the Browser pane. Provider per ADR-016.

## PASS condition

First meaningful data within 1 second of route load, measured.

## Measurement

`scripts/dashboard_audit.js`, installed BEFORE the route is switched to, watching with a
`MutationObserver` from the moment the route mounts. "Meaningful" means a figure that came from a
source: a balance, a limit, a fee rate. Not a skeleton, not a placeholder, not a zero.

```
first meaningful data:   11 ms
within one second:       yes
zero-during-load faults:  0
```

Full dashboard once loaded:

```
exit-balance             25.0000 tQUOTE
vault-balance            25.0000 tQUOTE
exit-withdraw            Withdraw 25.00
exit-pause               Resume
limit-maxOrderNotional   25 tQUOTE
limit-maxMarketNotional  50 tQUOTE
fee-disclosure           Fee: 50 basis points of each executed trade...
deposit-activate         Deposit 25.0000 and activate
```

## The fake win, and how it is refused

Named: "showing zeros while loading, which reads as 'you have nothing'."
Counter: "the loading state must be distinguishable from a real zero, as in task 4.7."

The audit samples every tracked numeric field repeatedly during the load window and fails on a bare
`0` or an empty string before that field's source has arrived. **Zero violations.** Fields render a
word while loading, never a number:

- the activation button reads "Reading your position..." and is DISABLED until the chain read
  completes, because `needsApproval` is a tri-state where `null` means unknown
- the limits panel reads "Loading the shipped defaults..."
- the fee line reads "Reading the fee from the contract..."
- a failed read renders `PanelError` with its source and reason, never a zero

## A defect this task found and fixed

First measurement: **11ms** to first meaningful data, from the exit bar, which reads the shared
position store and was already warm. But the dashboard's own panels were still ABSENT at 620ms and
only appeared at **1627ms**.

Cause: `PersonalView` and `ExitBar` each fetched `data/deployments.json` on mount, and `Activate`
fetched `data/limits.json` on mount. Switching routes unmounts and remounts them, so every visit
refetched both files before it could render anything. Neither file can change during a page load:
both are build artifacts, one written by the deploy script and one by `cargo test`.

`ui-v2/src/lib/manifest.ts` now caches both as module-level promises, shared by every consumer, with
concurrent callers joining the same in-flight request. A REJECTED promise is deliberately not cached,
so one network hiccup at startup cannot leave the page permanently unable to find its own contracts.

After the fix the panels are present by **980ms**, and first meaningful data is 11ms.

## GATE: PASS

11ms to first meaningful data against a 1000ms budget, and zero fields rendering a bare zero while
their source was still loading.
