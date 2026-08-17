# Task 9.8: failures are recoverable and never leave the user stuck

Run 2026-08-16. Every case induced in a live browser against the real deployment, not reasoned about.

## PASS condition

Five induced failures, five recoverable states, zero dead ends.

Named fake win: "a generic 'something went wrong' toast counted as handling."
Counter: "each case must name the specific cause and offer the specific next action."

So each case asserts FOUR things, not one:

1. the failure was genuinely induced, and the app did not silently succeed
2. the message names the SPECIFIC cause, matched against a per-case pattern
3. a way forward exists, as a next-action sentence or a control in the DOM
4. **RECOVERY**: after the cause is removed, the same path succeeds. A message that names a cause
   and offers an action nobody can complete is still a dead end.

## Results: 5 of 5, zero dead ends

| # | case | what the user sees |
|---|---|---|
| 1 | rejected signature | "You declined the connection request. Press Connect again and approve it in your wallet." + a Try again control |
| 2 | wrong chain | "Wrong network: your wallet is on chain 1. X Layer Testnet is chain 1952." + a Switch control |
| 3 | RPC failure | "Not updating: cannot reach the chain. The figure below is the last confirmed one. Check your connection; it will refresh by itself." |
| 4 | insufficient balance | "You asked to withdraw 1000000.0000 tQUOTE but only 50.0000 is available right now. Withdraw 50.0000 tQUOTE or less." |
| 5 | pause during deposit | "Paused while a deposit was in flight. The withdraw control stayed enabled, so you can still take your money out: pause stops the agent, never the exit." |

Each recovered: 1 reconnected on retry, 2 switched via 4902 then addEthereumChain, 3 resumed updating
when the network returned, 4 left the withdraw control working for a valid amount, 5 kept the exit
open throughout.

## THE DEFECT THIS TASK FOUND, and it was the real thing

Case 4 originally produced this in the UI, verbatim:

```
Error: Failed to estimate gas: server returned an error response: error code 3: execution
reverted, data: "0xcf47918100000000000000000000000000000000000000000000d3c21bcecceda1
0000000000000000000000000000000000000000000000000002b5e3af16b1880000"
```

Every fact a user needs is in there and none of it is legible. That is the named fake win in a
different costume: a hex dump fails the same test as a generic toast, because it says neither what
happened nor what to do.

`ui-v2/src/lib/revert.ts` now decodes seven of this project's custom errors into a cause and an
action. The same revert now reads:

> You asked to withdraw 1000000.0000 tQUOTE but only 50.0000 is available right now.
> Withdraw 50.0000 tQUOTE or less.

An UNRECOGNISED revert keeps its raw data and still offers a next action, because a user hitting an
error nobody anticipated is exactly the user most likely to be stuck.

**Three of the seven selectors were WRONG when first written by hand** (`DepositorPaused`,
`PermitExpired`, and `InvalidSignature` was missing its parentheses).
`scripts/verify-revert-selectors.sh` caught all three against `cast sig`. A wrong selector here does
not throw: the decoder simply never matches, the user silently gets the raw-hex fallback, and the
friendly message this file exists to produce never appears. That failure looks exactly like success
to any test that only asks "did an error render".

That is now the third time in this build that hand-written selectors were wrong, after five of eleven
in `lib/vault.ts`.

## A second real defect: silent staleness

Inducing an RPC outage showed the exit controls surviving, which is deliberate: the position store
keeps the last known position so the exit does not vanish at exactly the moment a user wants it.

But the user was told nothing. The balance kept displaying a figure that was no longer being
confirmed. A number that has quietly stopped updating invites a decision on stale data; one that
admits it is stale invites a refresh. The exit bar now renders the store's error as a named warning
while keeping the controls and the last figure.

## Three corrections to the AUDIT, not the product

Recorded because a gate that measures the wrong thing is worth as much attention as a bug.

1. **Insufficient balance was never induced.** The first version checked whether the Withdraw button
   was disabled while the account held 25 tQUOTE, so nothing was ever short. It now sends a
   withdrawal for 1e24 and asserts the decoded message.
2. **Pause was tested on an idle agent**, which is precisely the fake win task 8.7 names. It now
   starts a deposit, pauses while that transaction is in flight, and asserts the exit stays open.
3. **The action detector was too narrow.** It looked for verbs like "press" and "switch" and did not
   recognise "Withdraw 50.0000 tQUOTE or less" as an action, failing a case whose message was
   perfect. The product was right and the test was wrong.

## GATE: PASS

Five induced failures, five recoverable states, zero dead ends.
