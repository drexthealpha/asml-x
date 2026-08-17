"""Verify every path:line citation in evidence/ui-study.md against the studied clone.

A citation is `some/path.ext:12` or `some/path.ext:12-40` or `path.ext:12,17,29`. Paths are
resolved relative to the clone root, and also tried under apps/terminal/src/ and packages/,
because the study cites some files by their short form the way the prose reads.
"""
import os
import re
import sys

STUDY = os.environ["STUDY"]
SRC = os.environ["SRC"]

CITE = re.compile(r"`?([A-Za-z0-9_./$-]+\.(?:tsx?|css|json)):(\d[\d,\-]*)`?")

PREFIXES = ["", "apps/terminal/src/", "packages/", "apps/terminal/"]


_index = None


def build_index():
    """basename -> [full paths], built once, excluding node_modules and .git."""
    idx = {}
    for root, dirs, files in os.walk(SRC):
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", "public")]
        for f in files:
            idx.setdefault(f, []).append(os.path.join(root, f))
    return idx


def resolve(rel):
    for p in PREFIXES:
        full = os.path.join(SRC, p, rel)
        if os.path.isfile(full):
            return full
    # Fallback: the study cites some files by basename where the prose already established the
    # directory. Resolve those, but ONLY when the basename is unique in the clone. An ambiguous
    # basename is reported as unresolved rather than guessed, because picking one of several
    # candidates would turn a real citation into a plausible-looking wrong one.
    global _index
    if _index is None:
        _index = build_index()
    hits = _index.get(os.path.basename(rel), [])
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        print(f"  AMBIGUOUS  {rel}  matches {len(hits)} files in the clone")
    return None


def main():
    text = open(STUDY, encoding="utf-8").read()
    seen = []
    bad = 0
    lengths = {}

    for m in CITE.finditer(text):
        rel, lines = m.group(1), m.group(2)
        full = resolve(rel)
        if full is None:
            print(f"  BAD  {rel}:{lines}  FILE NOT FOUND in the clone")
            bad += 1
            continue
        if full not in lengths:
            with open(full, encoding="utf-8", errors="replace") as fh:
                lengths[full] = sum(1 for _ in fh)
        n = lengths[full]
        # A citation may be a list, a range, or a single number.
        nums = []
        for part in lines.split(","):
            part = part.strip()
            if not part:
                continue
            if "-" in part:
                a, _, b = part.partition("-")
                if a.isdigit():
                    nums.append(int(a))
                if b.isdigit():
                    nums.append(int(b))
            elif part.isdigit():
                nums.append(int(part))
        over = [x for x in nums if x > n]
        if over:
            print(f"  BAD  {rel}:{lines}  file has {n} lines, citation reaches {max(over)}")
            bad += 1
        else:
            seen.append((rel, lines))

    files = sorted({r for r, _ in seen})
    print(f"  citations checked: {len(seen) + bad}")
    print(f"  citations valid:   {len(seen)}")
    print(f"  citations BAD:     {bad}")
    print(f"  distinct files cited: {len(files)}")
    for f in files:
        cnt = sum(1 for r, _ in seen if r == f)
        print(f"    {cnt:3d}  {f}")

    threshold_ok = len(seen) >= 30
    print()
    print(f"  gate threshold is 30 citations: {'MET' if threshold_ok else 'NOT MET'}")
    return 0 if (bad == 0 and threshold_ok) else 1


if __name__ == "__main__":
    sys.exit(main())
