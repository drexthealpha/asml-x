"""Append the browser-verified section to evidence/phase9/connect.md.

A Python file rather than a heredoc, per R-WSL and E4. Passing this text through `wsl -c` with a
heredoc has now mangled a file four times in this build: backticks run as command substitution and
`$` expands, so a document about `eth_chainId` silently loses half its content. The rule exists
because of exactly this.
"""

OUT = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/phase9/connect.md"

SECTION = """
## Verified in the Browser pane

Build served from `ui-v2/dist` at `http://localhost:4173`, provider installed at document start.

### 1. Cold page with NO provider, before injection

The page rendered the no-wallet branch with a specific cause and a specific next action, not a
spinner and not a generic toast:

> No wallet found in this browser.
> Install OKX Wallet or MetaMask, then reload this page.

This is one of the five failure cases task 9.8 requires, verified here as a side effect of 9.0 being
outstanding.

### 2. Cold page WITH the provider, before any click

```
eth_accounts (before connect):    []
eth_chainId  (from the live RPC): 0x7a0
```

The page shows "Connect wallet" and does NOT open a wallet prompt on load. That is why the component
calls `eth_accounts` rather than `eth_requestAccounts` on mount: a page that prompts on load is the
behaviour task 9.2's landing surface must not have.

### 3. Connect, the task PASS condition

One click produced, read back out of the DOM:

```
data-address = 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
data-chain   = 1952
rendered     = "X Layer Testnet (1952)"
```

The address is the one `eth_requestAccounts` returned. The chain id is the one `eth_chainId`
returned from `https://testrpc.xlayer.tech`. Neither is a constant in the component: the gate reads
the data attributes the component wrote from provider responses, so a component that set local state
without touching a provider would have nothing to write.

### 4. Adversarial: wrong network, and recovery

Forcing the provider to report chain 1 and emitting `chainChanged`:

> 0x7BdD...dE46 | Wrong network: your wallet is on chain 1. |
> X Layer Testnet is chain 1952. | Switch to X Layer Testnet

The app did not silently continue against the wrong chain and did not dead-end. Clicking Switch drove
`wallet_switchEthereumChain`, which returned 4902, which triggered `wallet_addEthereumChain` followed
by a second switch. The surface recovered to the connected state.

### 5. Adversarial: user rejects the connection

With the provider returning EIP-1193 code 4001, which is what every wallet returns on Reject:

> You declined the connection request. |
> Press Connect again and approve it in your wallet. | Try again

`data-error-kind = user-rejected`. A named cause, a named next action, and a retry control. Clicking
Try again with approval restored the connected state, so the rejection is recoverable rather than
terminal.

### A note on how this was measured

The first attempt at sections 4 and 5 reported both as FAILING. They were not: the assertions ran
600ms to 800ms after emitting a provider event, and the React state transition had not settled. The
waits were raised and each step re-checked individually. Recording this because a 600ms wait that
passes on a fast run and fails on a slow one is a flaky gate, and a flaky gate eventually gets
believed in the wrong direction.

## What is NOT yet verified

The browser EXTENSION path. Task 9.0 is USER HANDLES and outstanding. Everything above ran against a
real key-backed EIP-1193 provider (ADR-016). What remains untested is the extension's confirmation
popup and its exact error surface. The same assertions re-run unchanged against an extension when 9.0
lands; if any fails there, the difference is in the extension and worth finding.

## GATE: PASS

Connecting from a cold page reached a known address and the correct chain. Three induced failures
(no provider, wrong chain, rejected signature) each produced a recoverable error naming the problem.
"""


def main():
    with open(OUT, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(SECTION)
    print(f"appended {len(SECTION.splitlines())} lines to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
