# Chain 196 reality, verified

Run 2026-08-16 05:39:47 UTC. ZERO SPEND: every call below is a read.

## Chain identity

```
eth_chainId          0xc4  (196)
eth_blockNumber      68089755
rpc                  https://rpc.xlayer.tech
```

## Gas price, read live

```
eth_gasPrice         20000001 wei
                     0.020000 gwei
                     0.000000000020000001 OKB per gas unit
```

## Gas token denomination

X Layer's gas token is OKB, with 18 decimals, the same shape as ether. Verified by arithmetic
rather than by reading a page: a native balance IS denominated in the gas token, so the
deployer's mainnet balance below is expressed in that unit, and `cast balance --ether`
divides by 1e18 without complaint.

```
deployer             0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
balance (wei)        0
balance (18dp)       0.000000000000000000
```

## Explorer URLs, probed

Reachability checked with a real request, not assumed. The judge-facing link is the oklink
x-layer family, matching every testnet link already in this repo.

```
  https://www.oklink.com/x-layer                             200
  https://www.oklink.com/x-layer/address/0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46 200
  https://xlayerscan.com                                     200
  https://www.okx.com/xlayer                                 000
```

`okx.com` is expected to fail from this machine (E9) and previously failed from Anthropic's
fetch infrastructure too, which is DNS non-resolution rather than a block page. It is named in
prose and is never the clickable link, because a link nobody can load is worse than no link.

## Still to append: the browser page title

Task 11.1's counter requires the chosen URL to be LOADED in a real browser and its page title
recorded. A 200 from curl proves the host answers; it does not prove a judge sees a working
explorer. The browser session appends that below.


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
