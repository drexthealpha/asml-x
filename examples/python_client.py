"""Minimal ASML-X coordination client. Standard library only, no dependencies.

Run the API first:
    ./target/release/asml-coord

Then:
    python3 examples/python_client.py

What this shows: an agent in another process reads the brain's view, sizes its own order against the
capacity it is offered, requests a quote, and accepts it. The quote passes through the SAME risk gate
an internal decision does, so a size the brain would refuse itself is refused here too.

Settlement is performed by the brain runtime, which owns the keystore. This endpoint never signs.
"""

import json
import os
import urllib.error
import urllib.request

BASE = os.environ.get("ASML_API", "http://127.0.0.1:8737")
KEY = os.environ.get("ASML_API_KEY", "demo-agent-key-1")


def call(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("x-api-key", KEY)
    if data:
        req.add_header("content-type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        # A refusal is an ANSWER. Every non-2xx here carries a JSON body explaining itself, and a
        # client that treats them as exceptions to swallow loses the reason.
        return e.code, json.loads(e.read() or b"{}")


def main() -> int:
    status, thesis = call("GET", "/thesis")
    print(f"[{status}] thesis: {thesis.get('thesis', '')[:100]}")
    print(f"       block {thesis.get('block')}, snapshot age {thesis.get('snapshot_age_ms')} ms")

    status, cap = call("GET", "/capacity")
    permitted = int(cap.get("max_permitted_size_micro", "0"))
    print(f"[{status}] capacity: {permitted} micro permitted, exposure {cap.get('current_exposure_micro')}")
    if cap.get("first_refusal_beyond"):
        print(f"       refuses beyond that with: {cap['first_refusal_beyond']}")

    # Size it yourself. Asking for exactly what you were offered is not a decision, and the gate is
    # there to refuse you if you get it wrong.
    size = max(permitted // 4, 500_000)
    side = "buy"

    status, quote = call("POST", "/quote", {"size_micro": str(size), "side": side})
    if status != 200:
        print(f"[{status}] quote refused: {quote.get('refusal') or quote.get('error')}")
        # The reducing side is what the engine is telling you to take.
        side = "sell"
        status, quote = call("POST", "/quote", {"size_micro": str(size), "side": side})
        if status != 200:
            print(f"[{status}] refused on both sides: {quote.get('refusal') or quote.get('error')}")
            return 1

    print(f"[{status}] quote {quote['quote_id']}: {side} {quote['size_micro']} at {quote['price_micro']}")
    print(f"       valid for {quote['ttl_ms']} ms, priced at block {quote['block']}")

    status, accepted = call("POST", "/accept", {"quote_id": quote["quote_id"]})
    print(f"[{status}] accepted: {accepted.get('accepted')}, handoff written: {accepted.get('handoff_written')}")
    print(f"       {accepted.get('note', '')}")
    return 0 if status == 200 else 1


if __name__ == "__main__":
    raise SystemExit(main())
