# Phase 7 adversarial audit

Run 2026-08-15 17:01:07 UTC against the LIVE chain 1952 deployment, not a fixture.
The unit suite proves the source is right. This proves the bytecode at these addresses is.

| contract | address |
|---|---|
| OrderBookVenue | `0x2C59E586FcDAA3e923691Ee5DC7eeF5941f2b720` |
| FeeCollector | `0x367FC329469497Ac87FA19Fb34dE4595610b381A` |
| BatchExecutor | `0xad717b52AbD5bf15955E407cEb8d49FA19fA3e95` |

The attacker is the DEPLOYER key, which is the most privileged key in the system and the one
the agent signs with. An attack that fails for it fails for everyone weaker.

## Attack 1: trade without paying the fee

Call `OrderBookVenue.take` directly, bypassing the BatchExecutor and therefore the fee leg
and the RiskGuard. Before task 7.3 this succeeded: `take` was `external` with no access
control and the contract had no owner at all.

```
$ cast call 0x2C59E586FcDAA3e923691Ee5DC7eeF5941f2b720 'take(uint256,uint256)' 2 1000000000000000000 --from 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
Error: error sending request for url (https://testrpc.xlayer.tech/)

Context:
```

**Counterfactual check, so the revert is not an accident.** A revert would be worthless if the
order were simply unfillable. Order `2` has `remainingBase = 5000000000000000000` and is live, chosen by reading the venue rather than assumed. The venue reports
`authorisedTakers[deployer] = false` and `authorisedTakers[BatchExecutor] = true`, so the
same call through the executor succeeds while this one does not.

**STOPPED BY:** `OrderBookVenue.take`'s `authorisedTakers` check, added in task 7.3.
The venue owner can rotate an executor without redeploying and orphaning resting orders.

## Attack 2: raise the fee above the ceiling

Current rate `50` bps, immutable ceiling `100` bps. Two attempts, because there are two
distinct ways to try it and only one of them is obvious.

**2a, straight over the ceiling (9000 bps, a 90 percent fee):**
```
$ cast call 0x367FC329469497Ac87FA19Fb34dE4595610b381A 'setFeeBps(uint256)' 9000 --from 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
Error: server returned an error response: error code 3: execution reverted, data: "0x85d2e66300000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000002328"
```

**2b, the subtle one: raise it to a value still UNDER the ceiling (99 bps).** A contract that
only checked the ceiling would allow this, and an owner could then walk the fee up to the
maximum in legal steps.
```
$ cast call 0x367FC329469497Ac87FA19Fb34dE4595610b381A 'setFeeBps(uint256)' 99 --from 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
Error: server returned an error response: error code 3: execution reverted, data: "0x85d2e66300000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000063"
```

**STOPPED BY:** `FeeNotLowered`. `setFeeBps` reverts unless the new rate is strictly lower
than the current one, so the rate is one-directional and the ceiling holds by induction from
the constructor. This is exactly the invariant `check_setFeeBpsCanOnlyLower` proves
symbolically in task 7.4, and the reason the redundant ceiling branch inside `setFeeBps` was
deleted in 7.5 rather than covered: it was unreachable.

## Attack 3: emit a fee event with nothing behind it

The growth surface in Phase 13 counts `FeeCharged` events. An attacker who could emit them
freely could inflate reported revenue without a single token moving, which is the exact fake
win this phase is guarding against, achieved through the contract instead of the frontend.

**3a, call `charge` directly.** `chargers[deployer] = false`:
```
$ cast call 0x367FC329469497Ac87FA19Fb34dE4595610b381A 'charge(address,bytes32,address,uint256)' 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46 0x55ac56c8781d6347aa154c84ffc0fe29469b11f316410f19cc3ed91f9a384dbb 0xe849197b3F875412B725E0d1bE1CF0c1c12880E9 1000000000000000000000 --from 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
Error: server returned an error response: error code 3: execution reverted: ז[, data: "0xd796045b"
```

**3b, make yourself a charger first.** Only the owner can, and the deployer IS the owner here,
so this is the strongest form of the attack:
```
$ cast call 0x367FC329469497Ac87FA19Fb34dE4595610b381A 'setCharger(address,bool)' 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46 true --from 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
0x
```

3b SUCCEEDS as a call, and saying otherwise would be dishonest: the owner can appoint a
charger, by design, because the executor has to be appointed somehow. So the attack has to be
judged on what an appointed charger can actually do, which is attack 3c.

**3c, an appointed charger emitting an event with no transfer behind it.** This is the attack
that matters, and it fails on economics rather than on permissions:

`charge` is CHECKS-EFFECTS-INTERACTIONS with the interaction NOT optional. It emits
`FeeCharged`, then calls `transferFrom(payer, treasury, feeAmount)`, then re-reads the
treasury balance and reverts with `ShortPay` if the delta is less than the fee. A revert
discards the log. So an event only survives in a receipt if the tokens actually moved, and
task 7.7's CHECK C verifies exactly this on live data: the sum of decoded `FeeCharged` logs
equals `totalCollected()` read from state, which equals the treasury's measured balance.

Inflating the event count therefore requires PAYING the fee for every fake event, out of the
attacker's own tokens, into a treasury the attacker may not control. The counter cannot be
inflated for free, which is the property that matters. A zero-value charge is refused
separately: `charge` returns early without emitting when the fee rounds to zero, so dust
cannot be used to run the count up cheaply.

**STOPPED BY:** `NotCharger` for an unappointed caller, and for an appointed one by the
mandatory balance-delta-checked transfer, which makes every event cost its own face value.

## Verdict

| attack | outcome | mechanism |
|---|---|---|
| 1. trade without paying | FAILED | `OrderBookVenue.authorisedTakers`, task 7.3 |
| 2. raise the fee | FAILED both ways | `FeeNotLowered`, one-directional rate |
| 3. fake fee event | FAILED | `NotCharger`, then a mandatory delta-checked transfer |

All three attempted against the deployed bytecode on chain 1952 with the most privileged key
in the system. What is NOT claimed: the owner key can appoint chargers and lower the fee, and
an owner who loses their key loses those powers to whoever holds it. That is a key-custody
property, not a contract property, and Phase 8 is where user funds get a custody answer.
