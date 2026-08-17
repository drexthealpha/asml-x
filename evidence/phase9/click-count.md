# Task 9.4: deposit and activate in three clicks or fewer

Run 2026-08-16 02:28:29 UTC.

## Post-activation state, read from chain

```
vault:                    0x3e938422f11D53b62F6Fe4afa2e4f52B1aFF4382
vault.balanceOf(user):    25000000000000000000
vault.maxNotional(user):  25000000000000000000
allowance(user, vault):   0   (0 means the permit was fully consumed)
token.nonces(user):       1   (1 means exactly one permit was used)
```

## The cold state this was measured from

`scripts/make-cold.sh` was run first and read back from chain:

```
allowance(user, vault): 0
vault.balanceOf(user):  0
token.nonces(user):     0
```

Zero allowance, zero balance, zero permit nonce. This is a first-time user, not an account that had
been through the flow before.

## The interactions, listed individually

Counted by `scripts/click_counter.js`, installed in the page AFTER connecting (the task counts "from
a connected wallet") and BEFORE the first activation click. It instruments two things:

- a **capturing** `click` listener on `document`, so a click is counted even if a handler stops
  propagation, and
- a wrapper around `window.ethereum.request`, so every call a real wallet would put behind a
  confirmation dialog is counted as the interaction it would be.

```
1  app-click:     deposit-activate  "Deposit 25.0000 and activate"
2  wallet-prompt: eth_signTypedData_v4      (a wallet shows a Sign dialog here)
3  wallet-prompt: eth_sendTransaction       (a wallet shows a Confirm dialog here)
```

```
appClicks:     1
walletPrompts: 2
TOTAL:         3
```

Methods a wallet answers WITHOUT prompting are excluded by an explicit list rather than by omission:
`eth_chainId`, `eth_accounts`, `eth_call`, `net_version`, `eth_blockNumber`. Every other method is
counted, so a method nobody thought about is counted rather than silently dropped.

## The transaction

```
0xb9efb6d9a7c466d5c5dc5855f37978b3520a987069f318c97a1bafaff06e97e3
```

https://www.oklink.com/x-layer-testnet/tx/0xb9efb6d9a7c466d5c5dc5855f37978b3520a987069f318c97a1bafaff06e97e3

Afterwards: balance 25e18, maxNotional 25e18, **allowance back to 0**, nonce 1. The permit granted
exactly the deposit amount and the same transaction consumed it, so nothing is left standing. That is
the reason ADR-017 rejected the shorter-looking option of requesting `type(uint256).max`.

## THE MEASUREMENT WAS WRONG TWICE BEFORE IT WAS RIGHT

Both failures are the same failure, and it is the one this task's fake win describes.

**First**, during task 9.3, the flow measured as ONE app click. The account held a 1e24 allowance
granted back in Phase 7, so the Approve step never rendered. One click was a true statement about
that account and a false statement about a new user.

**Second**, after redeploying for permit, it measured as one click AGAIN, because
`scripts/112c-vault-deploy.sh` approves the vault as part of deployment. The account was warm for a
different reason.

Both times the number was real and the claim would have been false. `make-cold.sh` now zeroes the
allowance and the balance, and this gate reads that cold state from chain before the browser is
touched, so warmth cannot be acquired by accident a third time.

## A defect the cold run exposed

With a cold account the button rendered `data-path="allowance"` and would have taken the plain
deposit path against a zero allowance, reverting. The cause: `needsApproval` was
`pos !== null && pos.allowanceWei < depositWei`, which is `false` both when an allowance exists and
when **nothing has been read yet**. The button was making a claim about chain state it had not read.

It is now a tri-state. `null` means unknown, the button is disabled and reads "Reading your
position...", and only a real answer selects a path. A boolean that collapses "no" and "I do not
know" into the same value is the same class of error as a UI that renders a failed read as a zero,
which task 9.7 forbids explicitly.

## GATE: PASS

Three interactions from a genuinely cold, connected wallet: one app click, one signature, one
transaction confirmation. Each is listed above. The count includes wallet confirmations, which is
what this task's fake win exists to prevent omitting.
