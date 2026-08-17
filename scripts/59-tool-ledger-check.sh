#!/usr/bin/env bash
# Tasks 1.18 and 10.5: no row in the tool ledger may remain PENDING.
# Every tool is USED, INSTALLED, SUBSTITUTED, NOT-INSTALLED (with a reason), or READ.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

LEDGER="$REPO/evidence/TOOL-USAGE.md"
OUT="$REPO/evidence/phase0/tool-ledger-check.txt"
mkdir -p "$(dirname "$OUT")"

{
echo "Tool ledger check, tasks 1.18 and 10.5"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

python3 - "$LEDGER" <<'PY'
import re, sys
rows = []
for line in open(sys.argv[1], encoding='utf-8'):
    s = line.strip()
    if not s.startswith('|') or s.startswith('|---') or s.startswith('| tool'):
        continue
    cols = [c.strip() for c in s.strip('|').split('|')]
    if len(cols) < 5:
        continue
    rows.append(cols[:5])

by_status = {}
for tool, status, task, produced, ev in rows:
    by_status.setdefault(status, []).append(tool)

print(f"total rows: {len(rows)}")
print()
for st in sorted(by_status):
    print(f"  {st:16} {len(by_status[st])}")
print()

pending = by_status.get('PENDING', [])
if pending:
    print(f"PENDING rows remaining: {len(pending)}")
    for t in pending:
        print(f"   - {t}")
else:
    print("No PENDING rows. Every tool is accounted for.")

# A NOT-INSTALLED or SUBSTITUTED row must carry a reason in the 'produced' column.
bad = []
for tool, status, task, produced, ev in rows:
    if status in ('NOT-INSTALLED', 'SUBSTITUTED') and len(produced) < 20:
        bad.append(tool)
if bad:
    print()
    print("Rows missing a real reason:")
    for t in bad:
        print(f"   - {t}")

# A USED row must carry an evidence path.
noev = [t for t, st, tk, pr, ev in rows if st == 'USED' and not ev.strip()]
if noev:
    print()
    print("USED rows with no evidence path:")
    for t in noev:
        print(f"   - {t}")

open('/tmp/ledger_pending', 'w').write(str(len(pending)))
PY

} | tee "$OUT"

PEND=$(cat /tmp/ledger_pending 2>/dev/null || echo 99)
echo
echo "pending=$PEND"
if [ "$PEND" != "0" ]; then
  echo "Ledger incomplete. This is expected before Phase 1 finishes; it must be 0 at 1.18."
  exit 1
fi
exit 0
