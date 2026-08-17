# Task 9.3: smart defaults, pre-selected and safe

Run 2026-08-15 22:18:19 UTC.

## The chain of equality this gate checks

```
Limits::conservative_testnet  ==  ui-v2/public/data/limits.json  ==  AgentVault.maxNotional(user)
      (the Rust crate)              (what the screen renders)         (what is actually onchain)
```

The task asks for two of these. The third, the crate, is included because it is the one that
rots quietly: a TypeScript constant holding 25 would let the engine change while the screen
kept saying 25. limits.json is WRITTEN BY the crate, so there is one definition.

## What the crate produced

```json
{
  "generatedBy": "cargo test -p risk-engine export_conservative_defaults_for_the_ui",
  "source": "crates/risk-engine/src/lib.rs Limits::conservative_testnet",
  "microPerUnit": 1000000,
  "limits": [
    {
      "key": "maxOrderNotional",
      "label": "Largest single order",
      "micro": 25000000,
      "protects": "Caps one bad decision. Nothing the agent does can risk more than this at once."
    },
    {
      "key": "maxMarketNotional",
      "label": "Largest position in one market",
      "micro": 50000000,
      "protects": "Stops the agent concentrating everything in a single market."
    },
    {
      "key": "maxGrossNotional",
      "label": "Total exposure across all markets",
      "micro": 200000000,
      "protects": "Bounds total risk even if every individual order is small."
    },
    {
      "key": "dailyLossLimit",
      "label": "Daily loss limit",
      "micro": 20000000,
      "protects": "Halts the agent for the day once losses reach this, rather than letting a bad day compound."
    },
    {
      "key": "maxConsecutiveLosses",
      "label": "Consecutive losing trades",
      "count": 4,
      "protects": "Halts the agent when it is repeatedly wrong, which usually means conditions changed."
    },
    {
      "key": "maxActionsPerMinute",
      "label": "Actions per minute",
      "count": 30,
      "protects": "A runaway guard. A loop that misfires cannot spend the account in seconds."
    }
  ]
}
```

## Read back from the deployed vault

```
vault:                       0xdF6f9503aE4e941F6055A945d940602FD729388F
depositor:                   0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
limits.json maxOrderNotional: 25000000000000000000 wei   (what the screen shows)
AgentVault.maxNotional:       25000000000000000000 wei   (what is enforced onchain)
AgentVault.balanceOf:         25000000000000000000 wei
```

The displayed default and the onchain limit are the SAME NUMBER. A user who touches nothing
runs under exactly the limit the risk engine ships.

## GATE: PASS

## How the onchain value got there: a real activation, driven by a UI click

The first run of this gate FAILED and was right to. It read `AgentVault.maxNotional = 1000000000000000000`
against a displayed default of `25000000000000000000`. That 1e18 was left over from task 8.3's
per-user limit test, not a default anybody chose. The gate's PASS condition is "proven by reading the
deployed vault state AFTER ACTIVATION", and no activation had happened yet, so the mismatch was the
gate correctly refusing to certify a stale number.

The activation was then performed through the interface, not from a shell:

```
click            "Deposit 25.0000 and activate"  (data-testid="deposit-activate")
transaction      0x725781ddd953f71d8458027104c94634ff8326ed1ac80599d9050c232a658021
result           vault.balanceOf     = 25000000000000000000
                 vault.maxNotional   = 25000000000000000000
```

Explorer: https://www.oklink.com/x-layer-testnet/tx/0x725781ddd953f71d8458027104c94634ff8326ed1ac80599d9050c232a658021

The transaction is real. The button's click handler called `eth_sendTransaction` on the injected
provider, which forwarded to the test signer, which shelled out to `cast send` with the keystore. The
key never entered the browser, so ADR-008's decision that signing lives in `cast` is preserved rather
than worked around. ADR-016 records why a real key-backed provider is used at all while task 9.0 is
outstanding.

## What the screen actually rendered

Read out of the DOM after connecting, from the `data-testid="limit-*"` nodes:

```
limit-maxOrderNotional     = 25 tQUOTE
limit-maxMarketNotional    = 50 tQUOTE
limit-maxGrossNotional     = 200 tQUOTE
limit-dailyLossLimit       = 20 tQUOTE
limit-maxConsecutiveLosses = 4
limit-maxActionsPerMinute  = 30
```

Each carries its one-line explanation of what it protects against, and those sentences live in the
generated file beside the number rather than in the component, so the explanation cannot drift from
the value it explains.

## Why the crate is the source

The task names two things that must agree, the UI and the chain. A third exists and it is the one
that rots quietly: a TypeScript constant holding `25`. With one, the engine could change while the
screen kept saying `25` and this gate would still pass, because the UI and the chain would agree with
each other and both be wrong.

So `ui-v2/public/data/limits.json` is WRITTEN BY `cargo test -p risk-engine
export_conservative_defaults_for_the_ui` from `Limits::conservative_testnet()`. That test also
ASSERTS each value, so an accidental change fails a test naming the number rather than silently
regenerating the file and letting the UI follow.

This gate regenerates the file before comparing, so it cannot pass against a stale copy.
