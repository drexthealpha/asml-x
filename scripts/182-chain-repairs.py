"""Task 16.2: repair what the reproduction inventory found, rather than footnoting it.

THINKING: #65 prioritisation (which defects actually threaten the chain's trustworthiness), #22
inversion (what would a hostile reader do with each of these).

TASKS.md 16.2 says anything that does not reproduce is CUT from the docs, not footnoted. Two of the
three defects here are CITATION errors rather than unreproducible claims, and the distinction
matters: cutting a claim whose evidence exists and whose runner exists, because the row pointed at
the wrong filename, would delete real work to satisfy a rule aimed at something else.

  1. C-710 appears TWICE. The second row is a rewrite of the first. Two rows sharing an id means any
     reference to [C-710] is ambiguous, so the superseded one is DELETED.
  2. C-906 cites `bash scripts/137-dashboard-audit.sh`, which has never existed. The real artefact is
     `scripts/dashboard_audit.js`, run in the Browser pane, and it is named inside the evidence file
     itself. The row is corrected to the path that reproduces it.
  3. C-907 cites `bash scripts/138-failure-paths.sh` with the same problem and the same fix.

If either JS file were missing too, the claim would be cut. They are present, so this is a repair.
"""
import os
import re
import sys

REPO = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"
CHAIN = f"{REPO}/evidence/CHAIN-OF-EVIDENCE.md"

REQUIRED = ["scripts/dashboard_audit.js", "scripts/failure_paths_audit.js"]


def main():
    for r in REQUIRED:
        if not os.path.exists(os.path.join(REPO, r)):
            print(f"MISSING {r}: the claim citing it must be CUT, not repaired. Stopping.")
            return 1

    lines = open(CHAIN, encoding="utf-8").read().split("\n")
    out = []
    seen_710 = False
    removed = 0
    fixed = 0

    for line in lines:
        if line.startswith("| C-710 "):
            if seen_710:
                # The LATER row is the rewrite and is the one kept, so the first is dropped only if
                # a second exists. Handled by keeping the last: see the second pass below.
                pass
            seen_710 = True

        out.append(line)

    # Keep the LAST C-710 and drop earlier ones: the later row is the rewritten, fuller version.
    idxs = [i for i, l in enumerate(out) if l.startswith("| C-710 ")]
    if len(idxs) > 1:
        for i in idxs[:-1]:
            out[i] = None
            removed += 1

    out = [l for l in out if l is not None]

    text = "\n".join(out)
    before = text
    text = text.replace(
        "bash scripts/137-dashboard-audit.sh",
        "serve ui-v2, then run scripts/dashboard_audit.js in the Browser pane",
    )
    text = text.replace(
        "bash scripts/138-failure-paths.sh",
        "serve ui-v2, then run scripts/failure_paths_audit.js in the Browser pane",
    )
    if text != before:
        fixed = 2

    open(CHAIN, "w", encoding="utf-8", newline="\n").write(text)
    print(f"removed superseded duplicate rows: {removed}")
    print(f"corrected command citations:       {fixed}")

    rows = [l for l in text.split("\n") if l.startswith("| C-")]
    ids = [l.split("|")[1].strip() for l in rows]
    print(f"rows now: {len(rows)}, distinct ids: {len(set(ids))}")
    return 0 if len(rows) == len(set(ids)) else 1


if __name__ == "__main__":
    sys.exit(main())
