"""Task 17.4: every claim in a judge-facing document carries a resolvable [C-xxx].

THINKING: #60 map-territory, #19 falsifiability.

Two directions, and both matter:

  FORWARD  every [C-xxx] cited in a judge-facing doc must resolve to a row in the chain. A dangling
           tag is worse than no tag: it looks like evidence and is not.
  BACKWARD every command and file a judge-facing doc tells the reader to run must exist. A guide
           that sends a judge to a missing script fails at the worst possible moment.

This is also the second half of task 12.7 and supersedes the ad-hoc part of
scripts/144-claim-consistency.sh, which is re-run alongside it.
"""
import os
import re
import sys

REPO = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"
CHAIN = f"{REPO}/evidence/CHAIN-OF-EVIDENCE.md"
DOCS = [
    "JUDGE-GUIDE.md",
    "README.md",
    "docs/limitations.md",
    "docs/COORDINATION-PROTOCOL.md",
    "docs/invariants.md",
    "docs/mainnet-path.md",
]
OUT = f"{REPO}/evidence/phase17/claim-tags.md"


def main():
    ids = set()
    for line in open(CHAIN, encoding="utf-8"):
        if line.startswith("| C-"):
            ids.add(line.split("|")[1].strip())

    dangling = []
    missing_cmds = []
    per_doc = {}

    for d in DOCS:
        path = os.path.join(REPO, d)
        if not os.path.exists(path):
            per_doc[d] = ("MISSING FILE", 0, 0)
            continue
        text = open(path, encoding="utf-8").read()

        tags = re.findall(r"\[(C-\d+)\]", text)
        bad = [t for t in set(tags) if t not in ids]
        dangling += [(d, t) for t in sorted(bad)]

        # Scripts the doc tells a reader to run.
        cmds = set(re.findall(r"scripts/([A-Za-z0-9_.-]+\.(?:sh|py|js))", text))
        for c in sorted(cmds):
            if not os.path.exists(os.path.join(REPO, "scripts", c)):
                missing_cmds.append((d, c))

        per_doc[d] = (f"{len(set(tags))} distinct tags", len(bad), len(cmds))

    L = []
    w = L.append
    w("# Task 17.4: claim tags, checked in both directions")
    w("")
    w(f"Chain holds **{len(ids)}** claim ids.")
    w("")
    w("| document | tags cited | dangling | scripts referenced |")
    w("|---|---|---|---|")
    for d, (t, bad, c) in per_doc.items():
        w(f"| `{d}` | {t} | {bad} | {c} |")
    w("")
    w("## Why both directions")
    w("")
    w("**Forward:** every `[C-xxx]` must resolve to a row. A dangling tag is worse than no tag,")
    w("because it looks like evidence and is not.")
    w("")
    w("**Backward:** every script a judge-facing document tells a reader to run must exist. A guide")
    w("that sends a judge to a missing script fails at the worst possible moment. Phase 16 found two")
    w("chain rows citing scripts that never existed, which is the same defect one layer down.")
    w("")
    if dangling:
        w("## DANGLING TAGS")
        w("")
        for d, t in dangling:
            w(f"- `{d}` cites `[{t}]`, which is not in the chain")
        w("")
    if missing_cmds:
        w("## MISSING SCRIPTS")
        w("")
        for d, c in missing_cmds:
            w(f"- `{d}` tells the reader to run `scripts/{c}`, which does not exist")
        w("")
    if not dangling and not missing_cmds:
        w("## Result")
        w("")
        w("**No dangling tags and no missing scripts.** Every claim tag in every judge-facing")
        w("document resolves to a row in the chain, and every script those documents name is present.")
        w("")
    w("## Reproduce")
    w("")
    w("```")
    w("python3 scripts/187-claim-tags.py")
    w("```")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")

    print(f"chain ids: {len(ids)}")
    for d, (t, bad, c) in per_doc.items():
        print(f"  {d:34} {t:20} dangling {bad}  scripts {c}")
    print(f"dangling tags:   {len(dangling)}")
    for d, t in dangling:
        print(f"   {d} -> {t}")
    print(f"missing scripts: {len(missing_cmds)}")
    for d, c in missing_cmds:
        print(f"   {d} -> scripts/{c}")
    print(f"written: {OUT}")
    return 0 if not dangling and not missing_cmds else 1


if __name__ == "__main__":
    sys.exit(main())
