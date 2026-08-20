"""Gate check 3: does the RWA surface carry the deep datapoints, or only a price?

A FILE, NOT INLINE. The inline version had nested quotes inside an f-string, which
`wsl -- bash -c` strips, producing a NameError that looked like a product failure. E4, thirteenth
occurrence.

WHAT IT DEMANDS. A price with a company name beside it is not integration. Each instrument has to
carry the record that lets a person judge it: what company it is a claim on, OKX's risk flags,
holder concentration, contract facts, and market figures. Any one of those missing on every
instrument is a fail, because it means the surface is showing a number and hiding the reason.

Reads the endpoint from argv so it works against the local feed server and the deployment.
"""
import json
import sys
import urllib.request

URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8787/api/rwafull"

REQUIRED = {
    "stock": "the company it is a claim on",
    "security": "the risk flags",
    "cluster": "holder concentration",
    "advanced": "contract facts",
    "market": "market figures",
}


def main():
    try:
        with urllib.request.urlopen(URL, timeout=30) as r:
            d = json.load(r)
    except Exception as e:
        print(f"  FAIL  {URL} did not return JSON: {e}")
        return 1

    instruments = d.get("instruments") or []
    if not instruments:
        print("  FAIL  no instruments returned")
        return 1

    bad = 0
    for key, what in REQUIRED.items():
        n = sum(1 for i in instruments if isinstance(i.get(key), dict) and i[key])
        if n:
            print(f"  PASS  {what}: {n}/{len(instruments)}")
        else:
            print(f"  FAIL  {what} missing on every instrument")
            bad = 1

    named = sum(1 for i in instruments if (i.get("stock") or {}).get("companyName"))
    print(f"  {'PASS' if named else 'FAIL'}  real company names: {named}/{len(instruments)}")
    if not named:
        bad = 1

    # The flag that matters most on this surface. Its ABSENCE is the failure, not its value.
    flagged = sum(1 for i in instruments if "isCounterfeitStockToken" in (i.get("security") or {}))
    print(f"  {'PASS' if flagged else 'FAIL'}  counterfeit check present: {flagged}/{len(instruments)}")
    if not flagged:
        bad = 1

    return bad


if __name__ == "__main__":
    sys.exit(main())
