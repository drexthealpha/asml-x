"""Append the real browser load of the explorer, task 11.1's counter."""

OUT = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/docs/verified/chain-196-reality.md"

SECTION = """

## The explorer, LOADED in a real browser

Task 11.1's named fake win is "recording an explorer URL that was never loaded", and its counter is
that the URL is loaded in a real browser and the page title recorded. A 200 from `curl` proves a host
answers; it does not prove a judge sees a working explorer.

Loaded 2026-08-16 in the Browser pane:

```
requested   https://www.oklink.com/x-layer/address/0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
resolved to https://www.oklink.com/x-layer/evm/address/0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
title       X Layer - EVM Address 0x7BdD...a5dE46 | Blockchain Explorer | OKLink
```

Checked on the rendered page rather than inferred from the title:

```
page names X Layer:     true
page shows the address:  true
```

The page renders an X Layer address view for the actual deployer address, with the navigation
("X Layer explorer", "Blockchain", "Tokens & NFTs", "Developers") and an `Address 0x7BdD2d0D17...`
heading. It is a working explorer, not a generic landing page.

### THE URL FORM CHANGED, and this matters for judge-facing links

The requested URL **redirected**: `/x-layer/address/<addr>` became `/x-layer/evm/address/<addr>`.
Both work, because the redirect is served, but the canonical form now carries `/evm/`.

Judge-facing links should use the canonical form directly:

```
address   https://www.oklink.com/x-layer/evm/address/<address>
tx        https://www.oklink.com/x-layer/tx/<hash>
```

A redirect is one more thing between a judge and the evidence, and redirects are exactly the kind of
detail that stops being served without warning. This was only visible because the page was actually
loaded: `curl -L` follows redirects silently and reports 200 for the old form, which is precisely why
the counter for this task exists.

## Summary of verified facts

| fact | value | how it was verified |
|---|---|---|
| chain id | 196 (`0xc4`) | `eth_chainId` on `https://rpc.xlayer.tech` |
| head block | 68,089,755 at the time of writing | `eth_blockNumber` |
| gas price | 20,000,001 wei (0.02 gwei) | `eth_gasPrice`, read live |
| gas token | OKB, 18 decimals | a native balance is denominated in the gas token by definition; `cast balance --ether` divides by 1e18 |
| deployer mainnet balance | **0 OKB** | `eth_getBalance`. Task 11.3 is USER HANDLES and gates Phase 12. |
| explorer | `www.oklink.com/x-layer/evm/address/<addr>` | loaded in a real browser, title and page content recorded above |
| secondary explorer | `xlayerscan.com` | 200 |
| okx.com | unreachable | DNS non-resolution from this machine and previously from Anthropic's fetch infrastructure. Named in prose, never linked. |
"""


def main():
    with open(OUT, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(SECTION)
    print(f"appended to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
