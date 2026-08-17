"""Format codebase-memory-mcp search_graph JSON into file:line lines.

Kept as a file, not an inline python -c, because the shell quoting around an f-string with
escaped double quotes broke on the first attempt.
"""
import json
import sys

raw = sys.stdin.read().strip()
try:
    d = json.loads(raw)
except Exception:
    print(raw[:900])
    raise SystemExit(0)

print("total=%s" % d.get("total"))
for r in d.get("results", []):
    print("  %-10s %-34s %s:%s" % (
        r.get("label", "?"),
        r.get("name", "?"),
        r.get("file_path", "?"),
        r.get("start_line", "?"),
    ))
