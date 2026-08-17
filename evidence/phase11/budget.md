# Mainnet budget, task 11.3

Gas price read LIVE from chain 196 at block 68097000: **20,000,001 wei** (0.0200 gwei).

Gas figures come from task 11.2's inventory: receipts where a transaction actually ran on
testnet, estimates against the live deployment otherwise. Nothing here is a guess.

## Deployments

Measured by `cast estimate --create` against chain 196, task 11.4. Not modelled.

```
contract                     gas
MockERC20 tBASE          723,067
MockERC20 tQUOTE         723,091
OrderBookVenue           842,999
RiskGuard                899,207
FeeCollector             596,290
BatchExecutor            591,800
AgentVault             1,145,009
TOTAL                  5,521,463
```

## Transactions

```
operation                            gas  count    subtotal
guard setMarketCap                30,467      1      30,467
guard setAgent                    30,467      2      60,934
token mint                        46,556      4     186,224
token approve                     46,556      4     186,224
venue setAuthorisedTaker          30,467      1      30,467
fee setCharger                    30,467      1      30,467
executor approveToken             46,556      3     139,668
venue postOrder                  170,404      4     681,616
agent cycle, take plus fee       255,459      3     766,377
user depositWithPermit           146,682      1     146,682
user withdrawAll                  52,842      1      52,842
user setPaused                    26,285      2      52,570
TOTAL                                             2,364,538
```

## The number

```
deployment gas             5,521,463
transaction gas            2,364,538
total gas                  7,886,001

gas price (live)          20,000,001 wei
cost                    157,720,027,886,001 wei
                        0.000157720 OKB

margin                  3x
BUDGET                  0.000473160 OKB
```

### Why a 3x margin and not a tighter one

Three things can each move the real cost, and none is under this project's control:

1. **Gas price moves.** The figure above is a spot read. X Layer's price has been stable at
   20,000,001 wei across every measurement in this build, but a budget set at exactly the
   spot price fails the first time it is not.
2. **Deployment gas is bounded, not measured.** The per-byte model is an upper bound on
   runtime code cost, and constructor execution is on top. The only way to measure a mainnet
   deployment exactly is to perform it.
3. **A failed transaction still costs gas.** A revert consumes what it used before reverting.
   Phase 12 has a dry run precisely to make this unlikely, not impossible.

The margin is stated here rather than folded silently into the headline, so a reader can
apply their own.

## USD

OKB's price is not readable from the chain and no price oracle is trusted for a budget line,
so the conversion is given as a table rather than a single figure that would pretend to a
precision it does not have.

```
  OKB at $ 20   ->   $0.0095
  OKB at $ 40   ->   $0.0189
  OKB at $ 60   ->   $0.0284
  OKB at $ 80   ->   $0.0379
```

## Current mainnet balance

```
deployer   0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46
balance    5000000000000000 wei (0.005000000 OKB)
```

**Sufficient.** The balance covers the 0.000473160 OKB budget.

## Reproduce

```
bash scripts/147-gas-inventory.sh    # measure gas on testnet
bash scripts/148-mainnet-budget.sh   # read the live price and compute this
```
