"""Append the activation detail to evidence/phase9/defaults.md.

A Python file rather than a heredoc, per R-WSL and E4.
"""

OUT = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/phase9/defaults.md"

SECTION = """
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
export_conservative_defaults_for_the_ui` from `Limits::conservative()`. That test also
ASSERTS each value, so an accidental change fails a test naming the number rather than silently
regenerating the file and letting the UI follow.

This gate regenerates the file before comparing, so it cannot pass against a stale copy.
"""


def main():
    with open(OUT, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(SECTION)
    print(f"appended to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
