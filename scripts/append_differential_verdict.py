"""Append the differential verdict: all three layers agreed, on selector AND arguments."""

OUT = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/phase14/differential.md"

SECTION = """

## VERDICT: all three agree

```
                        revert selector   decoded attempted        decoded cap
live deployed contract  0x3e2ed028        (same payload)           (same payload)
revm, in-memory EVM     0x3e2ed028        608000000000000000000    500000000000000000000
cast sig lookup         0x3e2ed028 = MarketCapExceeded(bytes32,uint256,uint256)
Rust risk engine        refuses at the type level: RiskApproved cannot be constructed
```

The agreement is on the **selector and the decoded arguments**, not on a boolean. revm reported the
attempted 608e18 against the cap of 500e18, which are the same two numbers the live contract encodes
in its revert payload. Two implementations that both refused for different reasons would have
coincided rather than agreed, and that difference is visible here.

The Rust engine's agreement is a stronger statement than a matching error code: `RiskApproved<T>` has
exactly one constructor and it sits behind this check, so an over-cap intent cannot produce an
approved value at all. It does not return an error, it fails to exist.

## The revm run in full

```
deployed into revm at 0x8F7a45eBDe059392E46A46DCc14AB24681A961Ea
setAgent:                          ok
setMarketCap(500e18):              ok
addExposure(8e18) under the cap:   ok      <- the negative control
addExposure(600e18):               REVERTED
revert selector:                   0x3e2ed028
decoded attempted:                 608000000000000000000
decoded cap:                       500000000000000000000
```

**The under-cap call succeeding is the control that matters.** Without it, a contract that reverted
on everything would pass this test, and the agreement would be meaningless. The 8e18 call is
accepted and the 600e18 call is refused by the same bytecode in the same run.

## What this rules out

A silent over-refusal, which is the failure no single layer can detect about itself. If the Rust
engine refused something the chain would have allowed, nothing would error: the agent would simply
under-trade, and the only symptom would be a system that is more cautious than it claims to be, for
a reason nobody could locate. Three-way agreement on the exact numbers is what closes that.
"""


def main():
    with open(OUT, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(SECTION)
    print(f"appended to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
