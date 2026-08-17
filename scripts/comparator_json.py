"""Turn the three captured comparator states into the JSON the UI renders.

PARSED from the agent's own `sidebyside` output, never re-derived. If the runtime's wording changes
this stops matching and the state is reported as UNPARSED rather than guessed, which is the safe
direction: a comparator that invents a verdict is worse than one that admits it could not read one.
"""

import json
import os
import re
import sys

REPO = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"
SRC = f"{REPO}/evidence/phase5/comparator"
OUT = f"{REPO}/ui-v2/public/data/comparator.json"

STATES = [
    ("healthy", "fresh oracle, not paused, no divergence, no redemption window nearby"),
    ("paused", "the issuer has paused the instrument on the vault"),
    ("diverged", "oracle and market price differ by more than the policy allows"),
]

BLOCK = re.compile(r"Live inputs, block (\d+)")
VAULT = re.compile(
    r"rwa vault:\s+oracle age (\d+)s, paused (\w+), until window (\d+)s, "
    r"divergence (-?\d+) bps, yield index ([\d.]+)"
)
ORDER = re.compile(r"Identical order: (.+)")
CRYPTO = re.compile(r"CRYPTO market \([^)]*\):\s*\n\s*(\w+)(.*)")
RWA = re.compile(r"RWA market \([^)]*\):\s*\n\s*(\w+)(.*)")
DIVERGENT = re.compile(r"DIVERGENT TREATMENT: (\w+)")
REASON = re.compile(r"RWA-SPECIFIC REASON: (\w+)")


def parse(path):
    if not os.path.exists(path):
        return {"parsed": False, "why": "capture file missing"}
    text = open(path, encoding="utf-8", errors="replace").read()

    def one(rx, *groups):
        m = rx.search(text)
        if not m:
            return None
        return m.group(*groups) if groups else m.group(0)

    vault = VAULT.search(text)
    crypto = CRYPTO.search(text)
    rwa = RWA.search(text)

    return {
        "parsed": bool(crypto and rwa),
        "block": int(one(BLOCK, 1)) if one(BLOCK, 1) else None,
        "order": (one(ORDER, 1) or "").strip(),
        "vault": {
            "oracleAgeSecs": int(vault.group(1)) if vault else None,
            "paused": (vault.group(2) == "true") if vault else None,
            "secondsUntilWindow": int(vault.group(3)) if vault else None,
            "divergenceBps": int(vault.group(4)) if vault else None,
            "yieldIndex": vault.group(5) if vault else None,
        },
        "crypto": {
            "verdict": crypto.group(1) if crypto else None,
            "detail": (crypto.group(2) or "").strip() if crypto else "",
        },
        "rwa": {
            "verdict": rwa.group(1) if rwa else None,
            "detail": (rwa.group(2) or "").strip() if rwa else "",
        },
        "divergentTreatment": one(DIVERGENT, 1) == "true",
        "rwaSpecificReason": one(REASON, 1) == "true",
    }


def main():
    out = {"generatedBy": "bash scripts/90-comparator-states.sh", "states": []}
    for name, setup in STATES:
        st = parse(f"{SRC}/{name}.txt")
        st["name"] = name
        st["setup"] = setup
        out["states"].append(st)
        print(
            f"  {name:9} parsed={st.get('parsed')} "
            f"crypto={st.get('crypto', {}).get('verdict')} "
            f"rwa={st.get('rwa', {}).get('verdict')} "
            f"divergent={st.get('divergentTreatment')}"
        )

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)
        fh.write("\n")
    print(f"  wrote {OUT}")

    # The healthy state is load-bearing: without BOTH approving, the RWA layer is indistinguishable
    # from a global brake, and the task names showing only refusals as its fake win.
    healthy = out["states"][0]
    ok_healthy = (
        healthy.get("parsed")
        and healthy["crypto"]["verdict"] == "APPROVED"
        and healthy["rwa"]["verdict"] == "APPROVED"
    )
    refusing = [s for s in out["states"][1:] if s.get("parsed") and s["rwa"]["verdict"] == "REFUSED"]

    print()
    print(f"  healthy shows both approving: {ok_healthy}")
    print(f"  refusing states captured:     {len(refusing)} of 2")
    if not ok_healthy:
        print("  The healthy capture does not show both markets approving, so the comparator would")
        print("  read as a global brake. Reported rather than shipped.")
    return 0 if (ok_healthy and len(refusing) == 2) else 1


if __name__ == "__main__":
    sys.exit(main())
