"""An external agent that pays for a quote over x402, then trades on it.

RUN IT:
    python3 examples/paying_agent.py

WHAT THIS DEMONSTRATES, and it is the whole point of agent-to-agent payments: a program written by
someone else, in another process, discovers that a resource costs money, pays for it autonomously,
and consumes it. No human approves the payment, no API key is exchanged, no account is created.

THE FLOW, exactly as x402 specifies it:

    1. POST /quote with no payment
    2. the server answers 402 with a challenge saying what it costs and where to pay
    3. the agent signs an authorization with its own wallet
    4. it retries the same request carrying PAYMENT-SIGNATURE
    5. the server serves the quote

WHY THIS MATTERS TO THE PRODUCT. ASML-X quotes are risk-gated: the price a caller gets has already
passed the same limits the agent applies to itself. Paying for one buys a quote that is safe to
act on, not a quote that is better. That distinction is enforced in the server, which runs the risk
gate identically whether or not payment was made, and it is the reason money cannot buy a
worse-for-the-user answer here.

SIGNING IS DELEGATED. `onchainos payment pay` signs from the TEE-held Agentic Wallet key. This file
never sees a private key, which is why it can be read, run and copied safely.
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

API = os.environ.get("ASML_API", "http://127.0.0.1:8080")
OOS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts", "oos.sh")


def post(path, payload, headers=None):
    """POST JSON. Returns (status, parsed body). A 402 is an ANSWER, not an error."""
    req = urllib.request.Request(
        f"{API}{path}",
        data=json.dumps(payload).encode(),
        headers={"content-type": "application/json", **(headers or {})},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        # 402 arrives here. It carries the challenge and is the expected first response.
        body = e.read()
        try:
            return e.code, json.loads(body)
        except json.JSONDecodeError:
            return e.code, {"raw": body.decode(errors="replace")}
    except urllib.error.URLError as e:
        print(f"cannot reach {API}: {e.reason}")
        print("start it with: cargo run -p coordination-api")
        sys.exit(1)


def sign_payment(challenge):
    """Sign an x402 authorization for this challenge, via the Agentic Wallet.

    Returns the header value, or None when the wallet is not logged in. `None` is a real outcome
    and is reported as such: an agent that cannot pay should say so, not pretend the resource was
    free.
    """
    accepts = (challenge.get("accepts") or [{}])[0]
    try:
        r = subprocess.run(
            ["bash", OOS, "payment", "pay",
             "--amount", str(accepts.get("maxAmountRequired", "")),
             "--pay-to", str(accepts.get("payTo", "")),
             "--asset", str(accepts.get("asset", "")),
             "--network", str(accepts.get("network", ""))],
            capture_output=True, text=True, timeout=90,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"  could not run the payment signer: {e}")
        return None

    i = r.stdout.find("{")
    if i < 0:
        print(f"  signer returned no JSON: {(r.stdout + r.stderr).strip()[:160]}")
        return None
    try:
        d = json.loads(r.stdout[i:])
    except json.JSONDecodeError:
        return None
    if not d.get("ok"):
        print(f"  signing refused: {str(d.get('error'))[:160]}")
        return None
    data = d.get("data") or {}
    return data.get("authorization_header") or data.get("paymentSignature")


def main():
    print(f"external agent → {API}")

    # ---- 1. ask without paying
    status, body = post("/quote", {"size_micro": "1000000", "side": "buy"})
    print(f"\n1. POST /quote unpaid → {status}")

    if status == 200:
        # Payment is not enabled on this instance. That is a valid configuration and the agent
        # simply proceeds; it does not invent a payment step that the server never asked for.
        print("   the server did not ask for payment; quote served")
        print(f"   {json.dumps(body)[:200]}")
        return 0

    if status != 402:
        print(f"   unexpected: {json.dumps(body)[:200]}")
        return 1

    accepts = (body.get("accepts") or [{}])[0]
    print(f"   payment required: {accepts.get('maxAmountRequired')} "
          f"{(accepts.get('extra') or {}).get('name')} on {accepts.get('network')}")
    print(f"   pay to: {accepts.get('payTo')}")

    # ---- 2. sign
    print("\n2. signing an authorization with the agent's own wallet")
    header = sign_payment(body)
    if not header:
        print("   no signature available, so no quote is requested.")
        print("   log in first:  bash scripts/oos.sh wallet login")
        return 1

    # ---- 3. retry, paid
    status, quote = post("/quote", {"size_micro": "1000000", "side": "buy"},
                         headers={"PAYMENT-SIGNATURE": header})
    print(f"\n3. POST /quote paid → {status}")
    if status != 200:
        print(f"   {json.dumps(quote)[:240]}")
        return 1

    print(f"   {json.dumps(quote, indent=2)[:400]}")
    print("\nThe quote above already passed the same risk limits the agent applies to itself.")
    print("Paying bought the quote. It did not buy a larger one.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
