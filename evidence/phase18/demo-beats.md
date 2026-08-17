# Task 18.1 verification: does the demo script describe the page that exists?

A demo script that tells a presenter to point at a panel which is not there fails on camera, in one
take, with no way to recover. So every beat was checked against the live built page rather than
against memory of what was built.

| beat the script relies on | present on the live page |
|---|---|
| MAINNET panel on the landing surface | yes |
| the words "chain 196" visible without navigating | yes |
| Connect control, or a clear no-wallet state | yes |
| "Run full demo" button | yes |
| "What the agent learned" panel | yes |
| `n = 10` sample size in the panel header | yes |
| net move showing 2000 and 391 | yes |
| hit rate 40.0% | yes |
| all five tabs reachable | yes |
| fee disclosure in basis points | **only after Connect** |

**9 of 10 confirmed on the live page.** The tenth is not a defect: the fee disclosure renders from
`pos.feeBps` inside `activate.tsx:310` and only exists once a wallet is connected, which the script's
own ordering already respects. It is called out in the script so the presenter does not reach for it
early, and it is the one beat that cannot be verified from here because acquiring a browser wallet
extension is a user-handled step.
