"""Task 16.1, step one: inventory every claim in the chain and check what it cites is really there.

THINKING: #49 evidence, #60 map-territory (the chain is a map of the artefacts; this asks whether the
territory matches), #19 falsifiability.

This runs BEFORE any re-execution, because a row citing a script that does not exist is a defect the
re-run would never surface: the runner would simply report a failure indistinguishable from a flaky
test. Existence and reproduction are separate questions and are answered separately.
"""
import json
import os
import re
import sys

REPO = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"
CHAIN = f"{REPO}/evidence/CHAIN-OF-EVIDENCE.md"


def parse():
    rows = []
    for line in open(CHAIN, encoding="utf-8"):
        if not line.startswith("| C-"):
            continue
        p = [x.strip() for x in line.split("|")]
        # ['', id, claim, evidence, command, status, task, date, '']
        if len(p) < 8:
            rows.append({"id": p[1] if len(p) > 1 else "?", "malformed": True})
            continue
        rows.append({
            "id": p[1],
            "claim": p[2],
            "evidence": p[3],
            "command": p[4],
            "status": p[5],
            "task": p[6],
            "date": p[7],
            "malformed": False,
        })
    return rows


def main():
    rows = parse()
    print(f"rows: {len(rows)}")

    malformed = [r for r in rows if r["malformed"]]
    dupes = {}
    for r in rows:
        dupes.setdefault(r["id"], 0)
        dupes[r["id"]] += 1
    dup_ids = [k for k, v in dupes.items() if v > 1]

    missing_files = []
    missing_cmds = []
    no_command = []

    for r in rows:
        if r["malformed"]:
            continue
        # Evidence column may list several comma-separated paths.
        for path in [p.strip() for p in r["evidence"].split(",")]:
            if not path or " " in path and not path.endswith((".md", ".txt", ".json", ".jsonl", ".sol", ".rs", ".tsx", ".ts")):
                continue
            full = os.path.join(REPO, path)
            if not os.path.exists(full) or os.path.getsize(full) == 0:
                missing_files.append((r["id"], path))

        cmd = r["command"]
        if not cmd:
            no_command.append(r["id"])
            continue
        # Every `bash scripts/X.sh` referenced must exist.
        for m in re.finditer(r"scripts/([A-Za-z0-9_.-]+\.(?:sh|py))", cmd):
            s = os.path.join(REPO, "scripts", m.group(1))
            if not os.path.exists(s):
                missing_cmds.append((r["id"], m.group(1)))

    print(f"malformed rows:        {len(malformed)}")
    print(f"duplicate ids:         {len(dup_ids)} {dup_ids[:6]}")
    print(f"rows with no command:  {len(no_command)} {no_command[:6]}")
    print(f"missing evidence files:{len(missing_files)}")
    for i, p in missing_files[:15]:
        print(f"   {i}  {p}")
    print(f"missing scripts:       {len(missing_cmds)}")
    for i, p in missing_cmds[:15]:
        print(f"   {i}  scripts/{p}")

    # Classify by whether re-running costs money or needs a key. This is what makes the Phase 16
    # report honest about what was actually re-executed.
    spends = []
    free = []
    for r in rows:
        if r["malformed"]:
            continue
        c = r["command"]
        if re.search(r"scripts/(1[0-9]{2}|[0-9]{1,2})-", c or ""):
            free.append(r["id"])
        else:
            spends.append(r["id"])

    out = {
        "rows": len(rows),
        "malformed": len(malformed),
        "duplicate_ids": dup_ids,
        "no_command": no_command,
        "missing_evidence": missing_files,
        "missing_scripts": missing_cmds,
    }
    with open(f"{REPO}/evidence/phase16/inventory.json", "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)

    ok = not malformed and not dup_ids and not missing_files and not missing_cmds and not no_command
    print()
    print("INVENTORY: " + ("CLEAN" if ok else "DEFECTS FOUND"))
    return 0 if ok else 1


if __name__ == "__main__":
    os.makedirs(f"{REPO}/evidence/phase16", exist_ok=True)
    sys.exit(main())
