#!/usr/bin/env python3
"""
An external agent. Separate process, separate language, no shared state with the brain.

This exists to satisfy the checklist item honestly. The named fake win was "the second
agent is a button in our own UI calling an internal function". So this is a standalone
Python program that speaks HTTP to the coordination API, keeps its own state, makes its
own decisions, and prints its own log.

It also acts adversarially on purpose. A coordination surface reachable by strangers
must be tested by a caller that misbehaves, so this agent deliberately tries: no API
key, an unknown key, a malformed body, an oversized request, another caller's quote, an
expired quote, a double-accept, and a burst that trips the rate limit.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("ASML_COORD", "http://127.0.0.1:8737")
KEY1 = "demo-agent-key-1"
KEY2 = "demo-agent-key-2"
MICRO = 1_000_000


def call(method, path, body=None, api_key=KEY1, raw_body=None):
    """Returns (status, parsed_json_or_text). Never raises on HTTP error status."""
    url = BASE + path
    data = None
    if raw_body is not None:
        data = raw_body.encode()
    elif body is not None:
        data = json.dumps(body).encode()

    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("content-type", "application/json")
    if api_key is not None:
        req.add_header("x-api-key", api_key)

    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        payload = e.read().decode()
        try:
            return e.code, json.loads(payload)
        except json.JSONDecodeError:
            return e.code, payload
    except urllib.error.URLError as e:
        return 0, f"connection failed: {e.reason}"


def show(label, status, payload):
    print(f"  [{status}] {label}")
    if isinstance(payload, dict):
        for k, v in payload.items():
            print(f"        {k}: {v}")
    else:
        print(f"        {payload}")
    return status, payload


def section(title):
    print()
    print("=" * 74)
    print(title)
    print("=" * 74)


def main():
    results = {"passed": 0, "failed": 0}

    def expect(label, got, want):
        ok = got == want
        results["passed" if ok else "failed"] += 1
        mark = "OK" if ok else "UNEXPECTED"
        print(f"        -> {mark}: got {got}, expected {want}")
        return ok

    section("0. reachability")
    status, payload = show("GET /health (no auth needed)", *call("GET", "/health", api_key=None))
    if status == 0:
        print()
        print("Coordination API is not running. Start it with:")
        print("  cargo run --release -p coordination-api")
        sys.exit(1)
    expect("health", status, 200)

    section("1. the happy path: read the brain's view, then trade against it")
    status, thesis = show("GET /thesis", *call("GET", "/thesis"))
    expect("thesis", status, 200)

    status, capacity = show("GET /capacity", *call("GET", "/capacity"))
    expect("capacity", status, 200)

    # Decide our own size from what the brain says it can take. This is the external
    # agent making its own decision, not being told what to do.
    max_permitted = int(capacity.get("max_permitted_size_micro", "0")) if isinstance(capacity, dict) else 0
    my_size = max(MICRO // 2, max_permitted // 2)
    print(f"\n  external agent decides: request {my_size / MICRO:.6f} base, half of the brain's stated capacity")

    status, quote = show(
        f"POST /quote size={my_size}",
        *call("POST", "/quote", {"size_micro": str(my_size), "side": "buy"}),
    )
    expect("quote issued", status, 200)

    if status == 200:
        qid = quote["quote_id"]
        status, accepted = show(f"POST /accept quote_id={qid}", *call("POST", "/accept", {"quote_id": qid}))
        expect("accept", status, 200)

        section("2. adversarial: a quote cannot be accepted twice")
        status, _ = show("POST /accept same quote again", *call("POST", "/accept", {"quote_id": qid}))
        expect("double accept refused", status, 409)

        section("3. adversarial: another caller cannot steal a quote")
        status, q2 = call("POST", "/quote", {"size_micro": str(MICRO // 2), "side": "buy"}, api_key=KEY1)
        if status == 200:
            status, _ = show(
                "POST /accept with agent-2's key on agent-1's quote",
                *call("POST", "/accept", {"quote_id": q2["quote_id"]}, api_key=KEY2),
            )
            expect("cross-caller accept refused", status, 403)

    section("4. adversarial: no API key")
    status, _ = show("GET /thesis without a key", *call("GET", "/thesis", api_key=None))
    expect("unauthenticated refused", status, 401)

    section("5. adversarial: unknown API key")
    status, _ = show("GET /thesis with a made-up key", *call("GET", "/thesis", api_key="not-a-real-key"))
    expect("unknown key refused", status, 401)

    section("6. adversarial: malformed body")
    status, _ = show("POST /quote with broken JSON", *call("POST", "/quote", raw_body="{not json at all"))
    expect("malformed body refused", status, 400)

    section("7. adversarial: request beyond the brain's risk capacity")
    huge = 10_000 * MICRO
    status, _ = show(f"POST /quote size={huge} (far beyond limits)", *call("POST", "/quote", {"size_micro": str(huge)}))
    expect("oversized request refused by the risk gate", status, 409)

    section("8. adversarial: an expired quote cannot be accepted")
    status, q3 = call("POST", "/quote", {"size_micro": str(MICRO // 2), "side": "buy"})
    if status == 200:
        ttl = q3.get("ttl_ms", 15000) / 1000.0
        print(f"  holding quote {q3['quote_id']} for {ttl + 1:.0f}s so it expires...")
        time.sleep(ttl + 1)
        status, _ = show("POST /accept on the expired quote", *call("POST", "/accept", {"quote_id": q3["quote_id"]}))
        expect("expired quote refused", status, 410)

    section("9. adversarial: burst until the rate limit trips")
    hit_limit = False
    for i in range(40):
        status, _ = call("GET", "/thesis", api_key=KEY2)
        if status == 429:
            print(f"  rate limit tripped on request {i + 1}")
            hit_limit = True
            break
    results["passed" if hit_limit else "failed"] += 1
    print(f"        -> {'OK' if hit_limit else 'UNEXPECTED'}: rate limit {'enforced' if hit_limit else 'never tripped'}")

    section("10. unknown endpoint")
    status, _ = show("GET /admin/drain-funds", *call("GET", "/admin/drain-funds"))
    expect("unknown endpoint refused", status, 404)

    section("summary")
    status, health = call("GET", "/health", api_key=None)
    print(f"  server counters: served={health.get('served')} refused={health.get('refused')}")
    print(f"  external agent checks passed: {results['passed']}")
    print(f"  external agent checks failed: {results['failed']}")
    print()
    print("  This agent ran in its own process, in Python, with no access to the")
    print("  brain's memory. Every refusal above came from the brain's own risk gate")
    print("  and auth layer over HTTP, not from a check inside this script.")

    sys.exit(0 if results["failed"] == 0 else 1)


if __name__ == "__main__":
    main()
