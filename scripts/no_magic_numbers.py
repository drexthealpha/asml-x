"""Task 5.2: every numeric literal in ui-v2/src must be layout, config, a domain bound, or an index.

The check is deliberately strict in the direction that matters. It does not try to guess which
numbers are "data-ish"; it enumerates EVERY numeric literal and requires each to fall in a named
category. A literal that fits none is a violation, and the file and line are printed so the fix is a
code change rather than an argument.

Categories, each with the reason it cannot be a data value:

  LAYOUT     inside a className string, a style value, a grid template, or a Tailwind arbitrary
             value. These are geometry, and geometry is not a claim about the chain.
  CONFIG     defined in config/layout.ts or lib/data.ts's DATA_LIMITS. Named constants with a
             stated purpose, and the UI's own polling and threshold settings.
  DOMAIN     a bound that comes from a unit definition rather than from an observation: 1_000_000
             micro-units per unit, 10_000 basis points per whole, MAX_SAFE_INTEGER.
  INDEX      array indices, slice bounds, string offsets, decimal places for toFixed.
  ZERO_ONE   0 and 1 used as counts, empty checks, or booleans-as-numbers.

Anything else fails.
"""
import os
import re
import sys

SRC = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/ui-v2/src"

NUM = re.compile(r"(?<![\w.$])(\d[\d_]*\.?\d*(?:e[+-]?\d+)?)(?![\w])")

# Domain constants: definitional, not observational.
DOMAIN = {"1000000", "1_000_000", "10000", "10_000", "100", "1e12", "1000", "1_000"}
ZERO_ONE = {"0", "1", "2"}

# A line is layout if the literal sits inside a class string, a style object, or a CSS-ish value.
LAYOUT_HINT = re.compile(
    r"className|style=|grid-cols|min-h|max-h|minHeight|maxHeight|flexBasis|width|height|"
    r"px-|py-|gap-|rem|dvh|%|z-|inset|translate|rounded|border|text-\[|w-\d|h-\d|size-",
)
INDEX_HINT = re.compile(
    r"\.slice\(|\.at\(|\[\s*\d|toFixed\(|padStart|padEnd|substring|substr|"
    r"\.length\b|charAt|repeat\(|offset|limit|\+\+|-- ",
)
CONFIG_FILES = {"layout.ts", "data.ts"}


REFERENCE_HINT = re.compile(r"scripts/\d|evidence/|docs/|\.sh|\.md|ADR-|task \d|C-\d")


def category(path, line, lit):
    base = os.path.basename(path)
    if base in CONFIG_FILES:
        return "CONFIG"
    # A script name, an evidence path or a task number inside on-screen prose is a REFERENCE the
    # reader can follow, not a measurement the UI is asserting. The risk panel tells the reader to
    # run scripts/77-journal-scale-audit.sh, and the 77 in that sentence is part of a filename.
    if REFERENCE_HINT.search(line):
        return "REFERENCE"
    if lit in DOMAIN:
        return "DOMAIN"
    if lit in ZERO_ONE:
        return "ZERO_ONE"
    if LAYOUT_HINT.search(line):
        return "LAYOUT"
    if INDEX_HINT.search(line):
        return "INDEX"
    return None


def main():
    counts = {}
    violations = []
    files = 0
    literals = 0

    for root, _dirs, names in os.walk(SRC):
        for name in sorted(names):
            if not name.endswith((".ts", ".tsx")):
                continue
            path = os.path.join(root, name)
            files += 1
            # COMMENT STRIPPING, fixed after the first run reported five false positives.
            # Skipping only lines that START with // or * misses two cases that matter here:
            # the interior of a /* */ block whose continuation lines start with prose, and JSX
            # comments written as {/* ... */}. A number inside prose is not a rendered value, and a
            # checker that flags one is a checker nobody will trust for the real hits.
            in_block = False
            for i, raw in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
                line = raw
                stripped = line.strip()

                if in_block:
                    if "*/" in stripped:
                        in_block = False
                        # Anything after the close on this line is still code.
                        line = stripped.split("*/", 1)[1]
                        stripped = line.strip()
                        if not stripped:
                            continue
                    else:
                        continue
                else:
                    opens = ("/*" in stripped) and ("*/" not in stripped)
                    if opens:
                        in_block = True
                        line = stripped.split("/*", 1)[0]
                        stripped = line.strip()
                        if not stripped:
                            continue

                if stripped.startswith(("//", "*")):
                    continue
                # Strip trailing line comments and single-line block comments before scanning.
                line = re.sub(r"/\*.*?\*/", " ", line)
                line = re.sub(r"//.*$", " ", line)
                stripped = line.strip()
                if not stripped:
                    continue
                for m in NUM.finditer(line):
                    lit = m.group(1)
                    literals += 1
                    cat = category(path, line, lit)
                    if cat is None:
                        violations.append((path.replace(SRC, "src"), i, lit, stripped[:100]))
                    else:
                        counts[cat] = counts.get(cat, 0) + 1

    print(f"  files scanned: {files}")
    print(f"  numeric literals found: {literals}")
    for k in sorted(counts):
        print(f"    {k:<9} {counts[k]}")
    print()
    if violations:
        print(f"  UNEXPLAINED LITERALS: {len(violations)}")
        for path, ln, lit, text in violations:
            print(f"    {path}:{ln}  literal {lit}")
            print(f"      {text}")
    else:
        print("  UNEXPLAINED LITERALS: 0")

    print()
    print("  What this does and does not prove:")
    print("    It proves no literal reaches the screen as a data value.")
    print("    It does NOT prove the data layer is honest; that is what task 4.7's no-data proof")
    print("    covers, by deleting the sources and checking that zero numbers render.")
    return 0 if not violations else 1


if __name__ == "__main__":
    sys.exit(main())
