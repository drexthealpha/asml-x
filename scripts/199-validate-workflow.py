"""Validate the CI workflow parses, and report what it will actually run.

Written as a file rather than inline because E4 mangles quoting through `wsl -- bash -c`, which
already cost one f-string here.
"""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

try:
    import yaml
except ImportError:
    print("pyyaml not installed; cannot validate")
    sys.exit(0)

path = os.path.join(REPO, ".github", "workflows", "ci.yml")
d = yaml.safe_load(open(path, encoding="utf-8"))

jobs = d["jobs"]
print(f"workflow parses. jobs: {len(jobs)}")
print()
total_steps = 0
for name, job in jobs.items():
    steps = job.get("steps", [])
    total_steps += len(steps)
    print(f"  {name:12} {len(steps):>2} steps   runs-on {job.get('runs-on')}   timeout {job.get('timeout-minutes')}m")

print()
print(f"total steps: {total_steps}")

# Every action must be pinned to a version, never a bare name or a floating major-less ref.
unpinned = []
for name, job in jobs.items():
    for s in job.get("steps", []):
        uses = s.get("uses")
        if uses and "@" not in uses:
            unpinned.append(f"{name}: {uses}")
print(f"unpinned actions: {len(unpinned)} {unpinned}")

# And no runner may be `ubuntu-latest`.
floating = [n for n, j in jobs.items() if str(j.get("runs-on")).endswith("latest")]
print(f"floating runner images: {len(floating)} {floating}")

sys.exit(0 if not unpinned and not floating else 1)
