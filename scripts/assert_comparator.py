"""Assert the comparator captured all three states with the right verdicts, task 5.5.

Checks, and each one exists because its absence would let a wrong artifact pass:

1. Three capture files exist, and the JSON the UI reads has three states.
2. HEALTHY has BOTH markets approving. Without it, the RWA layer is indistinguishable from a global
   brake, and TASKS.md names showing only the refusing states as this task's fake win.
3. Both refusing states have the RWA market REFUSED with an RWA-SPECIFIC cause named.
4. The CRYPTO market approved in EVERY state. This is the control: if crypto also refused, the
   difference would not be about the instrument at all, and the whole comparison would be void.
5. The refusal texts differ between the two refusing states. Two states that both refuse for the same
   reason are one state captured twice.
"""

import json
import os
import sys

REPO = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"
CAPTURES = f"{REPO}/evidence/phase5/comparator"
JSON_PATH = f"{REPO}/ui-v2/public/data/comparator.json"
NAMES = ["healthy", "paused", "diverged"]


def main():
    failures = []

    print("  1. capture files")
    for n in NAMES:
        p = f"{CAPTURES}/{n}.txt"
        ok = os.path.exists(p) and os.path.getsize(p) > 0
        print(f"     {n:9} {'present' if ok else 'MISSING'}  {p.replace(REPO + '/', '')}")
        if not ok:
            failures.append(f"capture {n} missing")

    if not os.path.exists(JSON_PATH):
        print(f"  JSON MISSING: {JSON_PATH}")
        return 1
    data = json.load(open(JSON_PATH, encoding="utf-8"))
    states = {s["name"]: s for s in data.get("states", [])}

    print()
    print("  2. verdicts, read from the JSON the UI renders")
    print(f"     {'state':10} {'crypto':10} {'rwa':10} {'rwa-specific':13} cause")
    for n in NAMES:
        s = states.get(n)
        if not s:
            failures.append(f"state {n} absent from JSON")
            print(f"     {n:10} ABSENT")
            continue
        cause = (s["rwa"]["detail"] or "").replace("REFUSED:", "").strip()[:52]
        print(
            f"     {n:10} {str(s['crypto']['verdict']):10} {str(s['rwa']['verdict']):10} "
            f"{str(s['rwaSpecificReason']):13} {cause}"
        )

    print()
    print("  3. the assertions")

    healthy = states.get("healthy")
    ok = bool(healthy) and healthy["crypto"]["verdict"] == "APPROVED" and healthy["rwa"]["verdict"] == "APPROVED"
    print(f"     healthy has BOTH markets approving:            {'yes' if ok else 'NO'}")
    if not ok:
        failures.append("healthy does not show both approving")

    for n in ("paused", "diverged"):
        s = states.get(n)
        refused = bool(s) and s["rwa"]["verdict"] == "REFUSED"
        specific = bool(s) and s["rwaSpecificReason"]
        print(f"     {n} refuses on the RWA side:{' ' * (21 - len(n))}{'yes' if refused else 'NO'}")
        print(f"     {n} names an RWA-specific cause:{' ' * (17 - len(n))}{'yes' if specific else 'NO'}")
        if not refused:
            failures.append(f"{n} did not refuse")
        if not specific:
            failures.append(f"{n} refusal is not RWA-specific")

    crypto_all = [s["crypto"]["verdict"] for s in states.values()]
    ctrl = all(v == "APPROVED" for v in crypto_all) and len(crypto_all) == 3
    print(f"     CONTROL, crypto approved in every state:       {'yes' if ctrl else 'NO'} {crypto_all}")
    if not ctrl:
        failures.append("crypto did not approve in every state, so the comparison is not isolating the instrument")

    causes = {
        n: (states[n]["rwa"]["detail"] or "").split("{")[0].strip()
        for n in ("paused", "diverged")
        if n in states
    }
    distinct = len(set(causes.values())) == 2
    print(f"     the two refusals have DIFFERENT causes:        {'yes' if distinct else 'NO'} {list(causes.values())}")
    if not distinct:
        failures.append("both refusing states gave the same cause, so one state was captured twice")

    print()
    if failures:
        print(f"  {len(failures)} FAILURE(S):")
        for f in failures:
            print(f"    - {f}")
        return 1
    print("  All five assertions hold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
