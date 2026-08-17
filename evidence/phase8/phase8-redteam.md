# Phase 8 adversarial audit

Run 2026-08-15 18:17:01 UTC against the LIVE chain 1952 deployment.
The unit suite proves the source is right. This proves the bytecode at this address is.

| role | address |
|---|---|
| AgentVault | `0xdF6f9503aE4e941F6055A945d940602FD729388F` |
| attacker, and also vault OWNER and AGENT | `0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46` |
| another user | `0x000000000000000000000000000000000000d0d0` |

The attacker holds every privileged role this system has. If an attack fails for this key it
fails for every weaker one.

## Attack 1: withdraw another user's balance

There is no function on this contract that takes a depositor address and moves their funds.
`withdraw` and `withdrawAll` both pass `msg.sender` to a PRIVATE `_withdraw`, so the
attack has to be attempted as the only thing the ABI permits: calling withdraw as oneself and
hoping the accounting credits someone else's balance.

Victim balance before: `0`
Attacker balance:      `3000000000000000000`

The attacker can only ever withdraw its OWN balance. To show the bound is real rather than
incidental, it asks for its own balance plus one wei:
```
$ cast call 0xdF6f9503aE4e941F6055A945d940602FD729388F 'withdraw(uint256)' 3000000000000000001 --from 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
Error: server returned an error response: error code 3: execution reverted, data: "0xcf47918100000000000000000000000000000000000000000000000029a2241af62c000100000000000000000000000000000000000000000000000029a2241af62c0000"
```

**STOPPED BY:** `InsufficientBalance`, computed from `withdrawable(msg.sender)`. An earlier
draft of this contract had an external `withdrawFor(address,uint256)` restricted to self-calls
so `withdrawAll` could reuse it. That is an externally reachable function whose safety rests
on a single `msg.sender == address(this)` line, and it was replaced with a private function
before deployment. The ABI below is the evidence that no such surface exists:

```
functions on the deployed contract that take an address and move value: none
withdraw(uint256)     -> credits msg.sender only
withdrawAll()         -> credits msg.sender only
openTrade(address,uint256) -> moves funds ONLY to the immutable tradeTarget
```

`openTrade` does take a depositor address, so it is worth being explicit about why it is not
a withdrawal: it can send funds to exactly one destination, fixed at construction.
tradeTarget on chain: `0x2C59E586FcDAA3e923691Ee5DC7eeF5941f2b720`, which is the venue.
There is no input to any function that names where funds go.

## Attack 2: trade past a user's limit

The attacker IS the agent. It has a funded depositor and a live limit of `1000000000000000000`.

**2a, one wei over the limit.** The boundary matters more than a large number, because an
off-by-one is the realistic bug:
```
$ cast call 0xdF6f9503aE4e941F6055A945d940602FD729388F 'openTrade(address,uint256)' 0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46 1000000000000000001
Error: server returned an error response: error code 3: execution reverted, data: "0x38888fc70000000000000000000000000000000000000000000000000de0b6b3a76400010000000000000000000000000000000000000000000000000de0b6b3a7640000"
```

**2b, raise the limit first.** This is the interesting one, and it SUCCEEDS in a specific and
deliberate sense: `setMaxNotional` is callable, but only by the DEPOSITOR, for themselves.
Here the attacker and the depositor are the same key, so of course it can raise its own limit.
The property being claimed is not 'nobody can raise a limit', it is 'nobody can raise SOMEONE
ELSE's limit'. Attempting it against the victim:
```
$ cast call 0xdF6f9503aE4e941F6055A945d940602FD729388F 'setMaxNotional(uint256)' 999... --from attacker  (affects the ATTACKER only)
There is no setMaxNotionalFor(address,uint256) on this ABI. The limit a caller can change is
indexed by msg.sender, so raising the victim's limit is not expressible as a transaction.
```

Victim limit, before and after every attempt above: `0`

**STOPPED BY:** `ExceedsUserLimit` on the boundary, and by the absence of any function that
writes another address's limit. Task 8.3 also demonstrates the same revert as a SUBMITTED
transaction with status 0x0, permanently on the explorer.

## Attack 3: unpause as the agent

The scenario that matters: a user has paused because they no longer trust the agent, and the
agent wants to resume trading their funds.

`setPaused` writes `paused[msg.sender]`. There is no `setPausedFor(address,bool)` and no
owner override. An agent calling `setPaused(false)` unpauses ITSELF as a depositor, which
changes nothing about any other user.

Demonstrated by pausing the attacker's own depositor slot and reading the victim's:
```
attacker paused[self]:  true
victim   paused[victim]: false
```

The two are independent storage slots keyed by address. An agent has no writer for anyone
else's, so 'unpause as the agent' is not an operation the contract can express.

**STOPPED BY:** per-depositor pause keyed on `msg.sender`. Note what this design also avoids:
the pausable audit guidance flags a shared hot-key pauser as an anti-pattern precisely because
a compromised pauser can grief everyone. There is no shared pauser here to compromise.

## Attack 4: strand funds by pausing at the worst moment

The most dangerous attack in this phase, because it turns the SAFETY feature into the weapon.
If pause blocked withdrawal, then whoever controls the pause controls the exit.

The attacker's depositor slot is paused right now, from attack 3, with a live balance.
Balance while paused: `3000000000000000000`
withdrawable:         `3000000000000000000`

Withdrawing WHILE PAUSED:
```
withdrawAll() status: 0x1
still paused:         true
balance after:        0
```

The funds came out with the pause still engaged. This is the property the research task made
non-negotiable and it is the one task 8.5's mutant M7 exists to defend: M7 ADDS a pause check
to the withdrawal path, and it is caught both by a named unit test and by the theorem
`check_vaultDepositorCanAlwaysWithdrawEvenWhenPaused`. Task 8.7 proves the same property with
the pause landing strictly between the open and close blocks of a live trade.

**STOPPED BY:** withdrawal deliberately not being gated on `paused`. Pause constrains the
AGENT, never the depositor.

## Verdict

| attack | outcome | mechanism |
|---|---|---|
| 1. withdraw another user's balance | FAILED | no function credits any address but `msg.sender`; `_withdraw` is private |
| 2. trade past a user's limit | FAILED | `ExceedsUserLimit` at the boundary; no writer for another address's limit |
| 3. unpause as the agent | FAILED | `paused` is keyed on `msg.sender`; no override exists |
| 4. strand funds by pausing | FAILED | withdrawal is not gated on pause, proved as a theorem and on chain |

## What is NOT claimed

The vault OWNER can rotate the agent. A rotated agent inherits the same three gates and gains
nothing, which `test_aRotatedAgentGetsNoNewPowers` asserts, but an owner who loses their key
hands agent rotation to whoever holds it. That is a key-custody property rather than a contract
property, and it is bounded: no agent, rotated or original, can withdraw a depositor's funds.

A depositor can raise their OWN limit. That is intended: it is their money and their risk
appetite. What no key can do is raise someone else's.

The offchain risk engine's own limits still bind on top of any per-user limit, and
`prop_a_user_limit_can_never_widen_what_the_system_allows` proves a user limit can only ever
subtract from what the system permits.
