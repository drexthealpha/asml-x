"""Task 2.1: extract factual assertions from judge-facing docs and assign claim ids.

Design notes that matter for whether the output is trustworthy:

- A "factual assertion" is defined MECHANICALLY, not by taste, so the extraction is
  reproducible: a sentence containing a number, an address, a hash, a version, a tool name, or
  one of a small set of claim verbs. Anything else is prose and is not indexed.
- Every row carries file and line. The task's named fake win is writing the inventory from
  memory of what v1 claimed, and a row that cannot say where it was read from is exactly that.
- Ids are assigned by sorted file order then line order, so re-running produces the SAME id for
  the same claim as long as the docs do not change. An inventory whose ids shuffle on every run
  cannot be cited from a document.
"""
import csv
import os
import re
import sys

REPO = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"

# Judge-facing surfaces only. Internal notes (TASKS.md, CLAUDE.md, RESUME.md) are excluded:
# they are not shipped, so a claim there is not a claim to a judge.
# JUDGE-GUIDE.md is at the REPO ROOT, not under docs/. The first run silently scanned 0 lines
# of it because the path was wrong and a missing file is skipped without complaint. That is the
# most dangerous kind of extraction bug: it produces a clean-looking inventory of the most
# judge-facing document in the repo with zero rows in it. Missing targets are now REPORTED.
TARGETS = [
    "README.md",
    "JUDGE-GUIDE.md",
    "docs/limitations.md",
    "docs/invariants.md",
    "docs/mainnet-path.md",
    "docs/research-basis.md",
]
TARGET_DIRS = ["docs/decisions", "docs/verified", "evidence/gates"]

NUM = re.compile(r"\b\d")
ADDR = re.compile(r"0x[0-9a-fA-F]{6,}")
VERB = re.compile(
    r"\b(is|are|was|were|has|have|does|do|proves?|proven|verified|deployed|returns?|"
    r"refus\w+|caught|passes|passed|failed|holds?|cannot|never|always|confirmed|"
    r"measured|observed)\b",
    re.I,
)
# Lines that are structure, not assertion.
SKIP = re.compile(r"^\s*(#{1,6}\s|\||```|-{3,}|\*{3,}|\d+\.\s*$|<!--)")


MISSING = []


def files():
    out = []
    for t in TARGETS:
        p = os.path.join(REPO, t)
        if os.path.exists(p):
            out.append(t)
        else:
            MISSING.append(t)
    for d in TARGET_DIRS:
        full = os.path.join(REPO, d)
        if not os.path.isdir(full):
            continue
        for name in sorted(os.listdir(full)):
            if name.endswith(".md"):
                out.append(os.path.join(d, name).replace("\\", "/"))
    return sorted(set(out))


def paragraphs(lines):
    """Yield (start_line, joined_text) for each prose paragraph, skipping fenced code.

    A bullet starts a new paragraph even without a blank line before it, because in these docs
    each bullet is its own claim and joining them would merge unrelated assertions.
    """
    out = []
    buf = []
    start = 0
    in_fence = False
    for i, raw in enumerate(lines, 1):
        line = raw.rstrip()
        if line.strip().startswith("```"):
            in_fence = not in_fence
            if buf:
                out.append((start, " ".join(buf)))
                buf = []
            continue
        if in_fence:
            continue
        bullet = bool(re.match(r"^\s*([-*+]|\d+[.)])\s", line))
        if not line.strip() or SKIP.match(line) or bullet:
            if buf:
                out.append((start, " ".join(buf)))
                buf = []
            if bullet:
                # Keep the bullet's own text as the start of a fresh paragraph.
                buf = [re.sub(r"^\s*([-*+]|\d+[.)])\s+", "", line).strip()]
                start = i
            continue
        if not buf:
            start = i
        buf.append(line.strip())
    if buf:
        out.append((start, " ".join(buf)))
    return out


def sentences(line):
    # Split on sentence enders but keep decimals and version numbers intact.
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z`\"'])", line.strip())
    return [p.strip() for p in parts if p.strip()]


# RECALL FIX. The first working version required a DIGIT in the sentence, and it found only 4
# assertions in a 236-line README. That is a bad trade: an inventory that misses claims is worse
# than one that over-includes, because 2.6 deletes claims that do not reproduce and a claim
# missing from the inventory is never checked at all. So a second rule accepts a claim verb plus
# a concrete SUBJECT even with no number in the sentence.
SUBJECT = re.compile(
    r"\b(halmos|hevm|scribble|kontrol|foundry|forge|cargo|clippy|proptest|river|duckdb|"
    r"gitleaks|paperscraper|alloy|revm|RiskGuard|RiskApproved|RwaVault|BatchExecutor|"
    r"Exchange OS|Onchain OS|X Layer|AggLayer|OP Stack|chain id|testnet|mainnet|"
    r"invariant|theorem|proof|mutant|contract|deployer|keystore|venue|agent|"
    r"risk engine|decision engine|journal|learner|limits?|cap|kill switch)\b",
    re.I,
)


def is_assertion(s):
    if len(s) < 25:
        return False
    if not VERB.search(s):
        return False
    if NUM.search(s) or ADDR.search(s):
        return True
    return bool(SUBJECT.search(s))


def kind(s):
    if ADDR.search(s):
        return "onchain"
    if re.search(r"\b(halmos|hevm|scribble|kontrol|theorem|invariant|proof|prove)\b", s, re.I):
        return "formal"
    if re.search(r"\b(mutant|mutation|test|proptest|coverage)\b", s, re.I):
        return "testing"
    if re.search(r"\b(chain|block|rpc|gas|tx|transaction|explorer)\b", s, re.I):
        return "chain"
    if re.search(r"\bversion|v?\d+\.\d+\.\d+\b", s, re.I):
        return "version"
    return "other"


def main():
    rows = []
    n = 0
    for rel in files():
        path = os.path.join(REPO, rel)
        try:
            lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
        except OSError as e:
            print(f"  UNREADABLE {rel}: {e}")
            continue
        # Paragraph-joining, added after the first run. Splitting per LINE produced fragments:
        # one row was the bare text of a markdown link because the sentence it belonged to
        # started on the previous line. Markdown hard-wraps prose, so a sentence is a
        # paragraph-level unit, not a line-level one. Each paragraph keeps the line number it
        # STARTS on, which is what a reader needs to find it.
        for start_line, para in paragraphs(lines):
            for s in sentences(para):
                if not is_assertion(s):
                    continue
                n += 1
                rows.append({
                    "claim_id": "C-%03d" % (200 + n),
                    "kind": kind(s),
                    "file": rel,
                    "line": start_line,
                    "assertion": s[:400],
                })

    per_file = {}
    for r in rows:
        per_file[r["file"]] = per_file.get(r["file"], 0) + 1

    print("  documents scanned: %d" % len(files()))
    if MISSING:
        print("  NAMED TARGETS NOT FOUND, which is a finding, not a warning to ignore:")
        for m in sorted(set(MISSING)):
            print("    MISSING %s" % m)
    print("  assertions extracted: %d" % len(rows))
    print()
    print("  per document:")
    for f in sorted(per_file, key=lambda k: -per_file[k]):
        print("    %-46s %3d" % (f, per_file[f]))

    per_kind = {}
    for r in rows:
        per_kind[r["kind"]] = per_kind.get(r["kind"], 0) + 1
    print()
    print("  by kind, which is what tells us where the verification effort has to go:")
    for k in sorted(per_kind, key=lambda k: -per_kind[k]):
        print("    %-10s %3d" % (k, per_kind[k]))

    out = os.path.join(REPO, "evidence/phase2/claim-inventory.csv")
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["claim_id", "kind", "file", "line", "assertion"])
        w.writeheader()
        w.writerows(rows)

    print()
    print("  first 12 rows, so the extraction can be judged rather than trusted:")
    for r in rows[:12]:
        print("    %s [%s] %s:%s" % (r["claim_id"], r["kind"], r["file"], r["line"]))
        print("      %s" % r["assertion"][:150])

    print()
    print("  csv: evidence/phase2/claim-inventory.csv")
    return 0 if rows else 1


if __name__ == "__main__":
    sys.exit(main())
