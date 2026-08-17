# Task 9.1: wallet connection

Run 2026-08-16 03:15:23 UTC.

## Which provider produced this evidence

**A real key-backed EIP-1193 provider, not a browser extension and not a stub.** Task 9.0
(install OKX Wallet or MetaMask) is USER HANDLES and outstanding. ADR-016 records why this is
verification rather than a fake win:

- the address is DERIVED from an actual X Layer testnet key, not a literal
- `eth_chainId` is answered by querying `https://testrpc.xlayer.tech`, not by returning `0x7a0`
- `eth_accounts` returns empty until `eth_requestAccounts` is called, so the cold-page
  behaviour under test is the real one

What it does NOT reproduce is the extension's confirmation popup. Task 9.4 accounts for that
explicitly instead of ignoring it, and this phase's gate report states that extension
verification is outstanding.

## Chain, read from the chain

```
eth_chainId via cast: 0x7a0 (1952)
expected by the UI:   0x7a0 (1952)
provider address:     0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
```

