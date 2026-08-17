"""Append the browser verification to the 9.9 evidence."""

OUT = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/phase9/fee-disclosure.md"

SECTION = """

## Verified in the Browser pane

After lowering the rate on chain from 50 to 49 bps, the page was reloaded and the disclosure read:

> Fee: **49** basis points of each executed trade, which is 49 tQUOTE on every 10,000 traded.
> Charged only when a trade executes, never on your deposit and never on withdrawal.

The chain was read INDEPENDENTLY in the same check, by calling `feeBps()` directly rather than
trusting the UI's own claim:

```
UI shows:            49 basis points
eth_call feeBps():   49
match:               true
```

The displayed figure changed because the contract changed. Nothing else in the build was touched
between the two readings, so no other explanation is available. That is what makes this a disclosure
rather than a caption.

## Why the test only lowers the fee

`setFeeBps` reverts on any raise. That is deliberate and proved twice: `test_feeCanOnlyBeLoweredNeverRaised`
in task 7.2, and `check_setFeeBpsCanOnlyLower` symbolically over every pair of rates in task 7.4.
So this gate walks the rate DOWN by one basis point and leaves it there. A restore step is absent
because it is impossible, not because it was forgotten.

The current live rate is therefore **49 bps**, down from the 50 it was deployed with. Task 7.x's
evidence quotes 50 because that was true when those gates ran; both figures are correct as of their
own timestamps, and the contract's own state is the authority.

## The disclosure is in plain words as well as basis points

The task asks for "the fee, in basis points and in plain words". The sentence carries both: "49 basis
points" and "49 tQUOTE on every 10,000 traded". It also states what is NOT charged, because the
question a user actually has is whether depositing or withdrawing costs them anything, and the answer
is no.

## GATE: PASS

No hardcoded fee rate anywhere in `ui-v2/src`, and the displayed figure tracked a live change to
`FeeCollector.feeBps()`.
"""


def main():
    with open(OUT, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(SECTION)
    print(f"appended to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
