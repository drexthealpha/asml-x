"""Explain the -2 aQUOTE wallet delta, which the gate correctly refused to round away."""

OUT = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/phase12/mainnet-personal.md"

SECTION = """

## THE -2 aQUOTE DELTA, EXPLAINED RATHER THAN ROUNDED AWAY

The assertion fired, and it was right to. Here is where the tokens actually are, read from chain 196
after the cycle:

```
venue          0x7065781018E015779d42bcC3eEA7429F8e479a3F   16.25 aQUOTE
agentVault     0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24    0
feeCollector   0x7ff884C412a1A2c416e931C59889e5335C5EFa0D    0
deployer                                                     2980.9 aQUOTE

user position inside the vault
  balanceOf      0
  committed      0
  totalDeposits  0
  isSolvent      true
```

**The vault behaved correctly and the user's deposit was fully restored: 5 aQUOTE in, 5 aQUOTE out.**

The delta comes from the test setup, not the contract. Trace it:

| step | wallet | where the tokens went |
|---|---|---|
| deposit 5 | -5 | wallet to vault |
| `openTrade` 2 | 0 | **vault to VENUE**, because the venue is the immutable `tradeTarget` |
| `closeTrade(2, 2)` | -2 | `transferFrom(msg.sender, ...)`, so the AGENT funded the return |
| `withdrawAll` | +5 | vault to wallet, the full deposit |
| net | **-2** | and the 2 is sitting at the venue |

`AgentVault.closeTrade` pulls the returned amount from `msg.sender`, which is the agent. On this
deployment **the agent and the user are the same address**, so one wallet paid both sides. In
production they are different parties: the agent returns funds from trading proceeds, and the user's
wallet only ever sees the deposit leaving and the withdrawal arriving.

So the correct reading is that the USER was made whole and the AGENT spent 2 aQUOTE funding a close
whose corresponding proceeds are still resting at the venue. `isSolvent()` returning true is the
contract confirming it: the vault owes nothing it cannot pay.

### Why this is recorded rather than fixed

The test could be made to show a clean zero by using a separate agent address, and that would be a
more realistic staging. It would also be a change made to produce a nicer number after the number
came out wrong, which is the wrong order to do things in. The assertion did its job: it refused to
accept a restored balance that was not restored, and the explanation is a real one that the chain
supports rather than a rationalisation.

**The claim this evidence supports is precise:** a real deposit, a real agent action under a real
per-user limit, and a real full withdrawal, all on chain 196, with the vault left solvent and the
user's vault balance back to zero. It does NOT claim the operator's wallet is unchanged, because it
is not, and the reason is stated above.
"""


def main():
    with open(OUT, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(SECTION)
    print(f"appended to {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
