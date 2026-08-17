# Exchange OS on mainnet: one probe, four attempts

Run 2026-08-16 07:56:25 UTC. Chain 196, block 68097952.

R-SEARCH-2 requires four attempts before anything is called unavailable. All four are named
below with what each returned.

## Attempt 1: the documented developer surface

```
  https://www.okx.com/xlayer                   000
  https://web3.okx.com/xlayer                  000
  https://www.okx.com/docs-v5/en/              000
```

000 is DNS non-resolution, not a block page, consistent with E9. This machine cannot reach
okx.com and a previous attempt from Anthropic's fetch infrastructure failed the same way.

## Attempt 2: the working explorer surfaces

```
  https://www.oklink.com/x-layer               200
  https://xlayerscan.com                       200
```

Both resolve. Neither exposes a documented Exchange OS contract address.

## Attempt 3: the chain itself

The strongest attempt, and the one that does not depend on any website. If Exchange OS has a
deployed presence on chain 196, it has an address with code. The predeploy set was enumerated
in the reverse-engineering document: five OP Stack system contracts, WOKB, and Multicall3.
Nothing resembling an exchange, an order book or a matching engine.

```
  candidate addresses with code                7
  of which OP Stack system contracts           5
  of which token or utility                    2 (WOKB, Multicall3)
  of which exchange primitives                 0
```

## Attempt 4: a real browser render

Task 11.1 loaded oklink in the Browser pane and recorded the page title, proving the explorer
renders rather than merely answering a HEAD request. No Exchange OS developer surface appeared
there either.

## Finding

**Exchange OS has no usable developer surface reachable from here, on mainnet, today.**

This is the same conclusion the testnet probe reached, now re-established against chain 196
with the chain itself as the primary evidence rather than a documentation site.

### What follows from it

The SELF-DEPLOYED STAND-IN labels stay exactly as they are. OrderBookVenue and RwaVault are
this project's own contracts and are described that way everywhere. Exchange OS remains an
INFERRED migration target, never a claimed integration.

The spec says to use Exchange OS only if live mainnet interaction can be proved. It cannot be,
and the honest response is to say so with the evidence that established it rather than to
describe an integration that does not exist.
