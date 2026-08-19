# WebSocket: authenticated, channels gated

`bash scripts/oos_ws.py` connects to `wss://wsdex.okx.com/ws/v6/dex`, authenticates with the
project API key, and receives `{"event":"login","code":"0"}`.

All three subscriptions are then refused by the server:

```
login ok
error: Only users who are in the whitelist are allowed to subscribe to this channel.   (price)
error: Only users who are in the whitelist are allowed to subscribe to this channel.   (trades)
error: Only users who are in the whitelist are allowed to subscribe to this channel.   (dex-token-candle1m)
```

## What this means

The credentials and the signature are correct: a bad signature fails at `login`, and login
succeeded. The refusal is an ACCOUNT PERMISSION. DEX WebSocket channels require the account to be
whitelisted by OKX; that is granted on their side and cannot be worked around from here.

## What the product does instead

REST polling through `scripts/feed_server.py`, at intervals matched to how fast each figure
actually moves. The UI labels the age of every number, so nothing is presented as live that is not.

This is a real limitation and is recorded rather than hidden. When the account is whitelisted,
`oos_ws.py` needs no change: the subscription arguments are already correct and the errors are the
server's, not the client's.

## E9 note

The machine's resolver cannot see okx.com, so the host is resolved over DNS-over-HTTPS and the
socket is opened to the resulting IP with the Host header and TLS SNI preserved. Ordinary DNS is
tried first, so this path is inert on any normally-resolving machine.

# ERC-8004 agent identity: blocked on wallet login

`bash scripts/oos.sh agent pre-check --role asp --chain xlayer` returns:

```
{"ok":false,"error":"no XLayer address found in current account"}
```

Registering an ERC-8004 identity requires an Agentic Wallet address, which requires the browser
social login. The API key authenticates every read surface but does not create a wallet.

The login URL was minted and handed over; until it is completed this task cannot proceed, and no
part of it can be faked. An identity registered against a wallet nobody controls would be worse
than none.
