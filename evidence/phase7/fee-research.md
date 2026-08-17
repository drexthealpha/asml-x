# Fee mechanism research, task 7.1

Run 2026-08-15 12:11:37 UTC. Solidity pin in this repo: 0.8.28
(contracts/foundry.toml), which matters because it is above the 0.8.24 transient-storage floor.

## Source reachability, checked rather than assumed
```
  https://speedrunethereum.com/guides/erc-4626-vaults            200
  https://ackee.xyz/blog/complete-reentrancy-hands-on-guide/     200
  https://detectors.auditbase.com/fee-on-transfer-solidity       200
  https://github.com/code-423n4/2022-05-cudos-findings/issues/3  200
```

## Primary sources used

1. **ERC-4626 vault risk catalogue**, speedrunethereum.com/guides/erc-4626-vaults. Names the risk set
   that applies to any vault holding third-party tokens: first-depositor inflation, reentrancy,
   fee-on-transfer and rebasing tokens, oracle manipulation, rounding drift.

2. **Code4rena finding, Cudos 2022, issue 3**, github.com/code-423n4/2022-05-cudos-findings/issues/3.
   A real audited finding rather than a tutorial: a protocol that trusted the `amount` argument
   instead of the observed balance delta mis-accounted every fee-on-transfer token that passed
   through it. This is the concrete failure the pattern below is designed around.

3. **Reentrancy guide**, ackee.xyz/blog/complete-reentrancy-hands-on-guide. Checks-effects-
   interactions, and specifically the case that applies here: in a vault holding a separate token
   contract, the attacker re-enters through the TOKEN's transfer callback during withdrawal, not
   through the vault's own external calls.

## What this project adopts

**Checks-effects-interactions, with state written before any token movement.** In `FeeCollector` the
accumulated-fee counter and the event are settled before `transferFrom` is called, so a reentrant call
observes the already-updated total.

**Transient-storage reentrancy guard (`TSTORE`/`TLOAD`).** Solidity 0.8.28 supports it. The sources
put the storage-based lock at roughly 5,000 gas against roughly 200 for the transient one, because
transient storage does not pay the EIP-2929 cold-access penalty. On a $20 mainnet budget where every
transaction is measured and published (task 12.6), a 4,800 gas saving per execution is not a
micro-optimisation, it is a line in the cost table.

**Balance-delta accounting, never the `amount` argument.** The fee is computed from the balance
actually received, measured before and after the transfer. This is the direct lesson of the Cudos
finding. It costs one extra `balanceOf` and removes an entire class of silent mis-accounting.

**A hard ceiling in immutable code.** `MAX_FEE_BPS` is a compile-time constant, and the owner setter
can only ever LOWER the fee. A fee that can be raised without limit is a theft primitive wearing an
`onlyOwner` modifier, and the whole point of this project is that limits are structural rather than
promised.

## PATTERN CONSIDERED AND REJECTED: performance fee on realized PnL only

The sources describe accruing fees when gains are realized, typically after a harvest, and basing the
fee on realized profit. It is the fairer model and it is what a real fund would use. It is rejected
here, and the reason is specific rather than a preference:

**This agent has no realized PnL yet.** `evidence/journal.jsonl` carries 43 decisions and zero closed
positions with a settled profit; realized PnL does not exist until task 14.4 builds it, and the
learning layer is at n=2 settled forecasts (ADR-011). A performance fee on realized profit would
therefore emit **zero fee events** for the entire demo and the entire mainnet window.

The spec's requirement is a business model that is live, visible, and increasing during the demo, with
its named fake win being a counter that increments in the frontend. A fee that structurally cannot
fire is worse than that fake win, because it would push the implementation toward faking the event to
have something to show.

So the model is a **usage fee on executed notional**: charged per risk-approved execution, emitted as
a real event, bounded by an immutable ceiling. It is honest about what it is. The README will say
"usage fee on notional", not "performance fee", because calling it a performance fee when it is
charged regardless of performance would be the same misrepresentation in the other direction.

**Revisit condition:** once 14.4 lands realized PnL, a performance component becomes possible and the
trade-off is worth re-examining. It is not possible before then, and this file is the record of why.

## What could still go wrong, and where it is caught

| risk | where it is caught |
|---|---|
| fee exceeds the ceiling for some notional | 7.4 halmos theorem over all inputs in range |
| emitted amount differs from the transferred amount | 7.4 theorem plus 7.5 mutation on the event value |
| execution path exists that skips the fee | 7.3 bypass test against the venue directly |
| fee-on-transfer token under-delivers | balance-delta accounting, asserted in the 7.2 test suite |
| reentrancy through the token during fee transfer | transient guard plus checks-effects-interactions |
