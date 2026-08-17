# Mainnet deployments, X Layer chain 196

Deployed 2026-08-16 08:10:10 UTC at block 68098775.

Status: DEMONSTRATED. Every address below was deployed by 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46 and its runtime
code was read back from chain with eth_getCode, because a deploy transaction that succeeds and
leaves no code is a thing that happens.

These are SELF-DEPLOYED contracts, not third-party venues. Task 11.6 established that Exchange
OS has no usable developer surface on mainnet, four ways. See docs/verified/exchangeos-mainnet.md.

| contract | address | deploy tx |
|---|---|---|
| aQUOTE | `0x12dcbE73416CDFe6de0681286C25ACe81B4644C0` | [`0xab5088576bf4adc6...`](https://www.oklink.com/x-layer/tx/0xab5088576bf4adc6d549a143d0176624f35ba59ba9050bbfe1d10da753440760) |
| aBASE | `0xEC23954ef24b22600C3b72C61CCE99cbe19A5AF5` | [`0x7f0df9e66b364ff8...`](https://www.oklink.com/x-layer/tx/0x7f0df9e66b364ff815cea31a2bcb43b790fceb6315283aacaa523330f110ecf3) |
| venue | `0x7065781018E015779d42bcC3eEA7429F8e479a3F` | [`0x04f3bc8b8b41ca37...`](https://www.oklink.com/x-layer/tx/0x04f3bc8b8b41ca373ddda5047126b312998bfc3c998315efa7e955b010a0e198) |
| guard | `0x9D22e538a72a5d2c9A28D08c27999216A78343C9` | [`0xacf02321f99778f1...`](https://www.oklink.com/x-layer/tx/0xacf02321f99778f1d631133b63d9a0f7a9e96c1edf0c1842d1cfa8ffdd2bf539) |
| fee | `0x7ff884C412a1A2c416e931C59889e5335C5EFa0D` | [`0x5cedcec2cf527897...`](https://www.oklink.com/x-layer/tx/0x5cedcec2cf527897cf3bc93c71597a7b63e8c4f366e54df67e2226eff72ec591) |
| exec | `0x7092050F3C4e72A2df8610ae2CC8c39DcA3B7f52` | [`0x5f76c2e865fb6db3...`](https://www.oklink.com/x-layer/tx/0x5f76c2e865fb6db378d14e065897375aac4c8568c6444992e723bf20c667f181) |
| vault | `0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24` | [`0xf862850d46cd38c3...`](https://www.oklink.com/x-layer/tx/0xf862850d46cd38c349678723a1dd84e983b24785e9f4a40482dc13c49b6a9759) |

Market id for aBASE/aQUOTE: `0x6b96e18e311cbaf06645140e28c8699906effa36fd1095ee0b6abe99542f9377`

Fee treasury: `0x000000000000000000000000000000000FEE0196`, deliberately NOT the deployer. Task 7.6 found that with
treasury == maker == deployer, fee revenue and trade proceeds land in the same balance and
revenue cannot be stated from balances at all.

## Explorer

- aQUOTE: https://www.oklink.com/x-layer/evm/address/0x12dcbE73416CDFe6de0681286C25ACe81B4644C0
- aBASE: https://www.oklink.com/x-layer/evm/address/0xEC23954ef24b22600C3b72C61CCE99cbe19A5AF5
- venue: https://www.oklink.com/x-layer/evm/address/0x7065781018E015779d42bcC3eEA7429F8e479a3F
- guard: https://www.oklink.com/x-layer/evm/address/0x9D22e538a72a5d2c9A28D08c27999216A78343C9
- fee: https://www.oklink.com/x-layer/evm/address/0x7ff884C412a1A2c416e931C59889e5335C5EFa0D
- exec: https://www.oklink.com/x-layer/evm/address/0x7092050F3C4e72A2df8610ae2CC8c39DcA3B7f52
- vault: https://www.oklink.com/x-layer/evm/address/0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24

## Cost of this step

```
balance before  5000000000000000 wei
balance after   4890606234530312 wei
spent           109393765469688 wei (0.000109394 OKB)
```
