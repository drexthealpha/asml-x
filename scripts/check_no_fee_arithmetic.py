#!/usr/bin/env python3
"""Task 7.7 CHECK A: assert no arithmetic on fee values exists anywhere in ui-v2/src.

WHY THIS IS NOT A GREP. The first version was, and it reported two failures that were not failures:
it matched the `*` opening a `/** Fee revenue ... */` doc comment, and the `/` inside the string
"scripts/fee_logs.py". Both are the operator characters, neither is an operation. A check that cries
wolf on its own documentation gets switched off, so it strips comments and string literals first and
searches only executable code.

WHAT IT LOOKS FOR: any arithmetic or accumulation applied to an identifier whose name contains "fee",
and any numeric coercion of one. That is the shape of Phase 7's headline fake win, "a counter
incremented in TypeScript on each decision".

WHAT IS DELIBERATELY ALLOWED: string indexing and slicing. `formatWei` inserts a decimal point into a
digit string with `padStart` and `slice`, never dividing by 1e18, because a wei total above 2**53
loses precision as a JavaScript number. Formatting is not computing, and the distinction is the
reason the panel formats the way it does.
"""
import pathlib
import re
import sys

SRC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "ui-v2/src")

# Replace comment and string contents with spaces, preserving line numbers and offsets so a hit still
# points at the right place.
PATTERNS = [
    (re.compile(r"/\*.*?\*/", re.S), None),
    (re.compile(r"//[^\n]*"), None),
    (re.compile(r'"(?:[^"\\\n]|\\.)*"'), None),
    (re.compile(r"'(?:[^'\\\n]|\\.)*'"), None),
    (re.compile(r"`(?:[^`\\]|\\.)*`", re.S), None),
]


def strip(text):
    for pat, _ in PATTERNS:
        text = pat.sub(lambda m: re.sub(r"[^\n]", " ", m.group()), text)
    return text


FEE_ID = r"[A-Za-z_$][A-Za-z_$0-9]*[Ff]ee[A-Za-z_$0-9]*|[Ff]ee[A-Za-z_$0-9]*"
CHECKS = [
    (re.compile(rf"\b(?:{FEE_ID})\s*(?:\+=|-=|\*=|/=|\+\+|--)"), "accumulation on a fee value"),
    (re.compile(rf"\b(?:{FEE_ID})\s*[-*/+]\s*[A-Za-z0-9_$(]"), "arithmetic on a fee value"),
    (re.compile(rf"[A-Za-z0-9_$)\]]\s*[-*/+]\s*\b(?:{FEE_ID})\b"), "arithmetic producing a fee value"),
    (re.compile(rf"\b(?:Number|parseFloat|parseInt|BigInt)\s*\(\s*[^)]*(?:{FEE_ID})"),
     "numeric coercion of a fee value"),
    (re.compile(rf"\.reduce\s*\([^)]*(?:{FEE_ID})"), "fold over fee values"),
]


def main():
    files = sorted(list(SRC.rglob("*.ts")) + list(SRC.rglob("*.tsx")))
    findings = []
    for f in files:
        code = strip(f.read_text(encoding="utf-8"))
        for i, line in enumerate(code.splitlines(), 1):
            for pat, why in CHECKS:
                m = pat.search(line)
                if m:
                    findings.append((f, i, why, m.group().strip()))

    print(f"  files searched: {len(files)}")
    print(f"  checks applied: {len(CHECKS)} (comments and string literals stripped first)")
    if not findings:
        print("  PASS  no arithmetic, accumulation or numeric coercion of any fee value")
        return 0
    print(f"  FAIL  {len(findings)} fee computation(s) in the frontend:")
    for f, i, why, snippet in findings:
        print(f"    {f}:{i}  {why}: {snippet!r}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
