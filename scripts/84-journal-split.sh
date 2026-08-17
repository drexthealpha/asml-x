#!/usr/bin/env bash
# Separate the pre-fix journal rows from the post-fix ones.
#
# THINKING: #60 map-territory (the live artifact must describe the current binary; the old rows are
# still a real record and are kept, not deleted), #49 evidence.
#
# WHY: the journal APPENDS. A fresh `asml run` added correct rows on top of the 87 rows written on
# 9 Aug by a binary that predated the wei_to_micro conversion, so the file contained both and the
# scale audit still failed. Deleting the old rows would destroy a real record of real decisions;
# leaving them in the live file makes every downstream number ambiguous. So: split.
#
# The boundary is POSITIONAL and known exactly: the file had 87 rows before this session's runs.
# The split is then VERIFIED by running the scale audit on each half, which is what turns a
# positional guess into a checked fact.
#
# EVIDENCE PATH: evidence/journal-legacy-2026-08-09.jsonl, evidence/journal.jsonl,
# evidence/phase4/journal-split.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase4/journal-split.txt"
J="$REPO/evidence/journal.jsonl"
LEGACY="$REPO/evidence/journal-legacy-2026-08-09.jsonl"
BOUNDARY=87

{
echo "Journal split, pre-fix rows separated from post-fix rows"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Before"
echo "  evidence/journal.jsonl: $(wc -l < "$J") rows"
echo "  boundary: row $BOUNDARY. Rows 1..$BOUNDARY were written on 9 Aug by a binary predating the"
echo "  wei_to_micro conversion at crates/market-intel/src/lib.rs:95-110. Everything after was"
echo "  written today by the current binary."
} 2>&1 | tee "$OUT"

head -n "$BOUNDARY" "$J" > "$LEGACY"
tail -n +"$((BOUNDARY + 1))" "$J" > /home/zulab/journal-current.jsonl
cp /home/zulab/journal-current.jsonl "$J"

{
echo
echo "## After"
echo "  evidence/journal.jsonl (current binary):        $(wc -l < "$J") rows"
echo "  evidence/journal-legacy-2026-08-09.jsonl:       $(wc -l < "$LEGACY") rows"
echo "  Nothing was deleted. The legacy rows are a real record of real decisions and stay in the"
echo "  repository, labelled by filename and by date."
echo
echo "## Verification, which is what makes the positional split a checked fact"
} | tee -a "$OUT"

/home/zulab/.asml-venv/bin/python - <<'PY' 2>&1 | tee -a "$OUT"
import json, re
NUMS = re.compile(r"got: (-?\d+), limit: (-?\d+)")
WEI = 10 ** 12

def audit(path, label):
    rows = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    wei = sane = 0
    tx = 0
    for r in rows:
        if r.get("tx_hash"):
            tx += 1
        for c in r.get("candidates", []):
            reason = c.get("rejection_reason")
            if not reason:
                continue
            m = NUMS.search(reason)
            if not m:
                continue
            if int(m.group(1)) > WEI:
                wei += 1
            else:
                sane += 1
    print(f"  {label}")
    print(f"    rows: {len(rows)}   transactions: {tx}")
    print(f"    limit refusals with a wei-scaled got: {wei}")
    print(f"    limit refusals with a plausible got:  {sane}")
    return wei

base = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence"
legacy_wei = audit(f"{base}/journal-legacy-2026-08-09.jsonl", "legacy (9 Aug, pre-fix)")
current_wei = audit(f"{base}/journal.jsonl", "current (this session, post-fix)")
print()
if legacy_wei > 0 and current_wei == 0:
    print("  SPLIT CONFIRMED: every wei-scaled value is on the legacy side and none on the current")
    print("  side, which is exactly what the boundary claim predicts.")
else:
    print(f"  SPLIT NOT CONFIRMED: legacy wei={legacy_wei}, current wei={current_wei}.")
    print("  The boundary is wrong and the numbers must not be quoted until it is right.")
PY
RC=${PIPESTATUS[0]}

echo | tee -a "$OUT"
echo "written: $OUT" | tee -a "$OUT"
