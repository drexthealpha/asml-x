"""Triage gitleaks findings by whether the file could ever reach the repository.

A working-tree scan reads gitignored build output too: target/, node_modules/, dist/. Findings there
cannot be committed, so they are noise in a gate that exists to stop secrets being published. But
"noise" is a judgement, so this prints the split rather than assuming it, and the CI config excludes
exactly the ignored paths rather than a hand-picked list of files.
"""
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPORT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/gl-final.json"


def ignored(path):
    r = subprocess.run(
        ["git", "check-ignore", "-q", path], cwd=REPO, capture_output=True
    )
    return r.returncode == 0


def main():
    try:
        findings = json.load(open(REPORT, encoding="utf-8"))
    except Exception as exc:
        print(f"cannot read {REPORT}: {exc}")
        return 1

    pushable, unreachable = [], []
    for f in findings:
        path = f.get("File", "?")
        rule = f.get("RuleID", "?")
        (unreachable if ignored(path) else pushable).append((rule, path))

    print(f"total findings: {len(findings)}")
    print()
    print(f"IN GITIGNORED PATHS (cannot be committed): {len(unreachable)}")
    for rule, path in unreachable:
        print(f"  {rule:24} {path}")
    print()
    print(f"IN PUSHABLE PATHS: {len(pushable)}")
    for rule, path in pushable:
        print(f"  {rule:24} {path}")

    return 0 if not pushable else 1


if __name__ == "__main__":
    sys.exit(main())
