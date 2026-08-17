#!/usr/bin/env bash
# Detect wei-scaled values in the journal, i.e. numbers that skipped the wei_to_micro conversion
# at the market-intel boundary.
#
# THINKING: #60 map-territory (the journal is what every claim reads, so its scale is a fact worth
# checking mechanically), #50 empirical, #7 counterfactual (a refusal with a plausible number and
# a refusal with a 1e30 number mean different things about the agent).
#
# WHY THIS EXISTS: the risk panel reads utilisation back out of refusal strings. Building it
# surfaced that every OrderNotionalTooLarge refusal in the 9 Aug journal carries a `got` of ~3e30
# against a 25e6 limit. Full write-up: evidence/phase4/journal-provenance.md
#
# EVIDENCE PATH: evidence/phase4/journal-scale-audit.txt
# PASS: zero wei-scaled refusals. A non-zero count means the journal predates the wei_to_micro
# fix and must be regenerated before any panel or document quotes its numbers.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase4/journal-scale-audit.txt"
mkdir -p "$(dirname "$OUT")"

{
echo "Journal scale audit"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Input"
echo "  file:     evidence/journal.jsonl"
echo "  written:  $(stat -c%y "$REPO/evidence/journal.jsonl" 2>/dev/null | cut -d. -f1)"
echo "  rows:     $(wc -l < "$REPO/evidence/journal.jsonl" 2>/dev/null)"
echo
echo "## Threshold"
echo "  WEI_PER_MICRO is 1e12 (crates/market-intel/src/lib.rs:60). A notional in micro-units for"
echo "  this demo is at most a few tens of millions, so any refusal reporting a got above 1e12 is"
echo "  a wei value that was never divided down."
echo
} 2>&1 | tee "$OUT"

/home/zulab/.asml-venv/bin/python "$REPO/scripts/journal_scale_audit.py" 2>&1 | tee -a "$OUT"
RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict"
if [ "${RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. No wei-scaled values. The journal's numbers can be quoted directly."
else
  echo "  RESULT: FAIL. The journal contains wei-scaled values, so it predates the"
  echo "  wei_to_micro conversion at crates/market-intel/src/lib.rs:95-110."
  echo "  The code is correct; the ARTIFACT is stale. Regenerate it with the current binary"
  echo "  (asml observe) before any panel or document quotes these numbers."
  echo "  Full finding: evidence/phase4/journal-provenance.md"
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit "${RC:-1}"
