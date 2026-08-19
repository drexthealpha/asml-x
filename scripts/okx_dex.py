"""OKX Onchain OS (DEX) client: signed v5 requests for real routes and quotes on X Layer.

AUTH. OKX v5 signs every request:
    OK-ACCESS-SIGN = base64(hmac_sha256(timestamp + method + requestPath + body, secret))
with OK-ACCESS-KEY, OK-ACCESS-TIMESTAMP (ISO-8601 with milliseconds and a Z), OK-ACCESS-PASSPHRASE
and, for the Web3/DEX surface, OK-ACCESS-PROJECT.

CREDENTIALS LIVE OUTSIDE THE REPO, at ~/.asml-keys/okx.env, the same place the deployer keystore
lives. Nothing here reads them from the working tree and nothing prints them.

E9. okx.com does not resolve on the build machine, so requests fall back to a pinned IP. Plain DNS
is tried first so this works unchanged in CI or on any other machine.
"""
import base64
import hashlib
import hmac
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV = os.path.expanduser("~/.asml-keys/okx.env")
HOST = "web3.okx.com"
PINNED_IP = "172.64.144.82"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36"


def creds():
    """Read credentials from outside the repo. Absent means absent, never a placeholder."""
    if not os.path.exists(ENV):
        return None
    out = {}
    for line in open(ENV, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    if not out.get("OKX_API_KEY") or not out.get("OKX_SECRET"):
        return None
    return out


def signed_get(path, c):
    """GET a signed OKX v5 endpoint. `path` includes the query string."""
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + f"{datetime.now(timezone.utc).microsecond // 1000:03d}Z"
    prehash = f"{ts}GET{path}"
    sign = base64.b64encode(
        hmac.new(c["OKX_SECRET"].encode(), prehash.encode(), hashlib.sha256).digest()
    ).decode()

    headers = [
        "-H", f"OK-ACCESS-KEY: {c['OKX_API_KEY']}",
        "-H", f"OK-ACCESS-SIGN: {sign}",
        "-H", f"OK-ACCESS-TIMESTAMP: {ts}",
        "-H", f"OK-ACCESS-PASSPHRASE: {c.get('OKX_PASSPHRASE','')}",
        "-H", "Content-Type: application/json",
        "-A", UA,
    ]
    if c.get("OKX_PROJECT"):
        headers += ["-H", f"OK-ACCESS-PROJECT: {c['OKX_PROJECT']}"]

    url = f"https://{HOST}{path}"
    for extra in ([], ["--resolve", f"{HOST}:443:{PINNED_IP}"]):
        try:
            r = subprocess.run(
                ["curl", "-sS", "--max-time", "30"] + headers + extra + [url],
                capture_output=True, text=True, timeout=45,
            )
            if r.returncode == 0 and r.stdout.strip():
                return json.loads(r.stdout)
        except Exception:
            continue
    return None


def signed_post(path, body, c):
    """POST a signed OKX v6 endpoint.

    The market-price endpoint is POST-only and answers a GET with
    `Request method 'GET' not supported`, which is why this exists alongside `signed_get`.

    THE SIGNATURE DIFFERS IN TWO PLACES and both matter: the method in the prehash is POST, and
    the SERIALISED BODY is appended to it. The body string signed here must be byte-identical to
    the one sent, so it is serialised exactly once and that same string is passed to curl. Building
    the JSON twice is the classic way to get a signature that is correct and still rejected.
    """
    payload = json.dumps(body, separators=(",", ":"))
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + f"{datetime.now(timezone.utc).microsecond // 1000:03d}Z"
    prehash = f"{ts}POST{path}{payload}"
    sign = base64.b64encode(
        hmac.new(c["OKX_SECRET"].encode(), prehash.encode(), hashlib.sha256).digest()
    ).decode()

    headers = [
        "-H", f"OK-ACCESS-KEY: {c['OKX_API_KEY']}",
        "-H", f"OK-ACCESS-SIGN: {sign}",
        "-H", f"OK-ACCESS-TIMESTAMP: {ts}",
        "-H", f"OK-ACCESS-PASSPHRASE: {c.get('OKX_PASSPHRASE','')}",
        "-H", "Content-Type: application/json",
        "-A", UA,
    ]
    if c.get("OKX_PROJECT"):
        headers += ["-H", f"OK-ACCESS-PROJECT: {c['OKX_PROJECT']}"]

    url = f"https://{HOST}{path}"
    for extra in ([], ["--resolve", f"{HOST}:443:{PINNED_IP}"]):
        try:
            r = subprocess.run(
                ["curl", "-sS", "--max-time", "30", "-X", "POST", "-d", payload]
                + headers + extra + [url],
                capture_output=True, text=True, timeout=45,
            )
            if r.returncode == 0 and r.stdout.strip():
                return json.loads(r.stdout)
        except Exception:
            continue
    return None


def main():
    c = creds()
    if not c:
        print(f"no credentials at {ENV}; DEX calls skipped")
        return 2

    # Imported lazily: tokens.py imports THIS module, so a top-level import would be circular.
    import tokens

    checks = [
        ("supported chains", "/api/v6/dex/aggregator/supported/chain"),
        ("X Layer tokens", "/api/v6/dex/aggregator/all-tokens?chainIndex=196"),
    ]
    try:
        # THIS CHECK WAS QUOTING THE WRONG ASSET AND SAYING SO. Its `toTokenAddress` was
        # 0x1e4a...d41d, which is USDT_Bridged, while the label read "quote 1 WOKB -> USDT".
        # X Layer lists both, they are different assets with different liquidity, and the label
        # asserted the one that was not being measured. Resolving by exact symbol removes the
        # possibility of the two drifting apart again.
        checks.append((
            "quote 1 WOKB -> USDT",
            f"/api/v6/dex/aggregator/quote?chainIndex=196&amount={tokens.units('WOKB', 1, c)}"
            f"&fromTokenAddress={tokens.address('WOKB', c)}"
            f"&toTokenAddress={tokens.address('USDT', c)}",
        ))
    except tokens.TokenNotListed as e:
        print(f"  skipping the quote probe: {e}")

    ok = 0
    for label, path in checks:
        d = signed_get(path, c)
        code = (d or {}).get("code", "no response")
        msg = (d or {}).get("msg", "")
        n = len((d or {}).get("data") or [])
        print(f"  {label:26} code={code} rows={n} {msg[:60]}")
        if code == "0":
            ok += 1
    print(f"{ok} of {len(checks)} DEX endpoints authenticated")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
