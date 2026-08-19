"""Real-time WebSocket to OKX Onchain OS DEX. Pushes, not polls.

WHY A DIRECT SOCKET RATHER THAN THE CLI. `onchainos ws start` would not open `price` or `trades`
for chain 196, so rather than retry the flags a second time the protocol reference in the skills
repo was read and the socket opened directly. The protocol is fully documented, which makes this a
supported path rather than a workaround:
`skills/okx-dex-market/references/market-ws-protocol.md`.

WHY WEBSOCKET AT ALL. Polling every four seconds is four seconds of staleness plus a request the
API serves whether or not anything changed. `price` pushes on change, so the number on screen moves
when the market moves. That is the difference between a live product and one whose price a person
reasonably assumes is hardcoded.

THE PROTOCOL, verbatim from the reference:

  endpoint   wss://wsdex.okx.com/ws/v6/dex
  login      {"op":"login","args":[{apiKey, passphrase, timestamp, sign}]}
  prehash    timestamp + "GET/users/self/verify"
  sign       base64(hmac_sha256(secret, prehash))
  ack        {"event":"login","code":"0"}  — code 0 is success, wait for it before subscribing
  subscribe  {"op":"subscribe","args":[{channel, chainIndex, tokenContractAddress}]}
  push       {"arg":{channel,...},"data":[{...}]}

NOTE THE DIFFERENT SIGNATURE. The REST scheme signs `timestamp + METHOD + path + body` with an ISO
timestamp. This one signs a fixed literal with a UNIX-SECONDS timestamp. Reusing the REST signer
here fails authentication with no useful message, which is exactly the kind of thing worth writing
down once.
"""
import base64
import hashlib
import hmac
import json
import os
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "ui-v2", "public", "data", "live.json")

WS_URL = "wss://wsdex.okx.com/ws/v6/dex"
CHAIN_INDEX = "196"
MAX_TRADES = 40


def resolve_doh(host):
    """Resolve a hostname over DNS-over-HTTPS, for the E9 case where the local resolver cannot.

    Returns the first A record, or None. Cloudflare's resolver is reachable from this machine even
    though okx.com is not, which is what makes this work.
    """
    import subprocess

    try:
        r = subprocess.run(
            ["curl", "-s", "--max-time", "10", "-H", "accept: application/dns-json",
             f"https://1.1.1.1/dns-query?name={host}&type=A"],
            capture_output=True, text=True, timeout=20,
        )
        answers = json.loads(r.stdout).get("Answer") or []
        for a in answers:
            if a.get("type") == 1 and a.get("data"):
                return a["data"]
    except Exception:
        pass
    return None


def login_message(key, secret, passphrase):
    ts = str(int(time.time()))
    prehash = ts + "GET/users/self/verify"
    sign = base64.b64encode(
        hmac.new(secret.encode(), prehash.encode(), hashlib.sha256).digest()
    ).decode()
    return {
        "op": "login",
        "args": [{"apiKey": key, "passphrase": passphrase, "timestamp": ts, "sign": sign}],
    }


def main():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from okx_dex import creds
    import tokens as tokenlist

    try:
        import websocket  # websocket-client
    except ImportError:
        print("websocket-client is not installed. Run: pip install websocket-client")
        return 1

    c = creds()
    if not c:
        print("no credentials at ~/.asml-keys/okx.env")
        return 1

    try:
        wokb = tokenlist.address("WOKB", c)
    except tokenlist.TokenNotListed as e:
        print(f"cannot resolve WOKB: {e}")
        return 1

    state = {
        "source": "OKX Onchain OS DEX WebSocket",
        "endpoint": WS_URL,
        "chain_id": int(CHAIN_INDEX),
        "token": "WOKB",
        "latest_price": None,
        "trades": [],
        "candles": [],
    }

    seconds = int(os.environ.get("WS_SECONDS", "25"))
    deadline = time.time() + seconds
    subscribed = []

    # E9: this machine's resolver cannot see okx.com, so the host is resolved over DNS-over-HTTPS
    # and the socket is opened to the resulting IP. `host` keeps the correct Host header and
    # `server_hostname` keeps the correct TLS SNI, so the server still sees a normal request to
    # wsdex.okx.com; only the name lookup is bypassed. Ordinary DNS is tried first so this works
    # unchanged on any machine that is not behind this resolver.
    url, opts = WS_URL, {"timeout": 15}
    try:
        import socket

        socket.getaddrinfo("wsdex.okx.com", 443)
    except socket.gaierror:
        ip = resolve_doh("wsdex.okx.com")
        if not ip:
            print("could not resolve wsdex.okx.com over DoH either")
            return 1
        url = f"wss://{ip}/ws/v6/dex"
        opts["host"] = "wsdex.okx.com"
        opts["sslopt"] = {"server_hostname": "wsdex.okx.com"}
        opts["header"] = ["Host: wsdex.okx.com"]
        print(f"  resolver cannot see okx.com; pinned to {ip}")

    print(f"connecting to {WS_URL}")
    ws = websocket.create_connection(url, **opts)
    try:
        ws.send(json.dumps(login_message(c["OKX_API_KEY"], c["OKX_SECRET"], c.get("OKX_PASSPHRASE", ""))))

        # WAIT FOR THE ACK before subscribing. Subscribing early is silently dropped, which looks
        # like a channel that carries no data rather than a sequencing mistake.
        ws.settimeout(10)
        logged_in = False
        while time.time() < deadline:
            try:
                msg = json.loads(ws.recv())
            except Exception:
                break
            if msg.get("event") == "login":
                if msg.get("code") == "0":
                    logged_in = True
                    print("  login ok")
                else:
                    print(f"  login FAILED: {msg.get('msg')}")
                    return 1
                break

        if not logged_in:
            print("  no login ack")
            return 1

        ws.send(json.dumps({
            "op": "subscribe",
            "args": [
                {"channel": "price", "chainIndex": CHAIN_INDEX, "tokenContractAddress": wokb},
                {"channel": "trades", "chainIndex": CHAIN_INDEX, "tokenContractAddress": wokb},
                {"channel": "dex-token-candle1m", "chainIndex": CHAIN_INDEX,
                 "tokenContractAddress": wokb},
            ],
        }))

        ws.settimeout(3)
        pushes = 0
        while time.time() < deadline:
            try:
                msg = json.loads(ws.recv())
            except Exception:
                continue

            event = msg.get("event")
            if event == "subscribe":
                ch = (msg.get("arg") or {}).get("channel")
                subscribed.append(ch)
                print(f"  subscribed {ch}")
                continue
            if event == "error":
                print(f"  error: {msg.get('msg')}")
                continue

            channel = (msg.get("arg") or {}).get("channel", "")
            for d in msg.get("data") or []:
                pushes += 1
                if channel == "price":
                    p = d.get("price")
                    if p:
                        state["latest_price"] = str(p)
                elif channel == "trades":
                    state["trades"].insert(0, {
                        "side": d.get("side") or d.get("type"),
                        "price": d.get("price"),
                        "amount": d.get("volume") or d.get("amount"),
                        "ts": d.get("ts") or d.get("time"),
                    })
                    del state["trades"][MAX_TRADES:]
                elif channel.startswith("dex-token-candle"):
                    state["candles"].append({
                        "t": int(d.get("ts", 0)) // 1000,
                        "o": d.get("o"), "h": d.get("h"), "l": d.get("l"), "c": d.get("c"),
                    })
                    del state["candles"][:-120]

        print(f"  pushes received {pushes}")
    finally:
        try:
            ws.close()
        except Exception:
            pass

    state["subscribed"] = subscribed
    state["fetched_at_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(state, fh, indent=2)

    print(f"  latest price  {state['latest_price']}")
    print(f"  trades        {len(state['trades'])}")
    print(f"  candles       {len(state['candles'])}")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
