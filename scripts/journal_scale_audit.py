"""Count refusals in the journal whose numbers are wei-scaled rather than micro-scaled."""
import json
import re
import sys

PATH = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/journal.jsonl"
NUMS = re.compile(r"got: (-?\d+), limit: (-?\d+)")
# WEI_PER_MICRO is 1e12. A legitimate micro notional here is at most tens of millions.
WEI_SUSPECT = 10**12


def main():
    try:
        rows = [json.loads(l) for l in open(PATH, encoding="utf-8") if l.strip()]
    except Exception as e:
        print(f"  could not read the journal: {e}")
        return 1

    sane = 0
    weird = 0
    examples = []
    by_reason = {}

    for r in rows:
        for c in r.get("candidates", []):
            reason = c.get("rejection_reason")
            if not reason:
                continue
            # Strip the "risk refused: " prefix the engine adds, so the variant name is the key.
            #
            # `split(":")[-1]` was wrong and produced the label "25000000 }": the refusal text
            # contains "got:" and "limit:" so the LAST colon is inside the numbers. Take the text
            # after the FIRST colon-space, then cut at the brace.
            body = reason.split(": ", 1)[-1] if ": " in reason else reason
            name = body.split("{")[0].strip() or reason
            by_reason[name] = by_reason.get(name, 0) + 1
            m = NUMS.search(reason)
            if not m:
                continue
            got = int(m.group(1))
            limit = int(m.group(2))
            if got > WEI_SUSPECT:
                weird += 1
                if len(examples) < 3:
                    examples.append(
                        (r.get("decision_id"), c.get("label", "")[:70], got, limit)
                    )
            else:
                sane += 1

    print(f"  refusals by reason: {by_reason}")
    print(f"  refusals with a plausible got:  {sane}")
    print(f"  refusals with a wei-scaled got: {weird}")
    if examples:
        print("  examples:")
        for did, label, got, limit in examples:
            ratio = got / limit if limit else float("inf")
            print(f"    decision {did}: {label}")
            print(f"      got {got} against limit {limit}, ratio {ratio:.3e}")

    baseline = sum(
        1
        for r in rows
        if str(r.get("thesis", "")).startswith("naive baseline")
        or str(r.get("risk_verdict", "")).startswith("baseline:")
    )
    print(f"  naive-baseline control rows in the file: {baseline} of {len(rows)}")
    return 0 if weird == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
