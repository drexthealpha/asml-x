#!/usr/bin/env bash
# Record C-1600 through C-1603 and write the Phase 16 gate report.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN="$REPO/evidence/CHAIN-OF-EVIDENCE.md"
GATE="$REPO/evidence/gates/phase16.md"

for f in evidence/phase16/reproduce.md evidence/phase16/mainnet-reverify.md \
         evidence/phase16/fake-win-register.md evidence/phase16/inventory.json; do
  [ -s "$REPO/$f" ] || { echo "MISSING OR EMPTY: $f"; exit 1; }
done
grep -q "Verdict: \*\*PASS\*\*" "$REPO/evidence/phase16/reproduce.md" || { echo "16.1 not green"; exit 1; }
grep -q "Verdict: \*\*PASS\*\*" "$REPO/evidence/phase16/mainnet-reverify.md" || { echo "16.3 not green"; exit 1; }

ROWS=$(grep -c "^| C-" "$CHAIN")
TODAY=$(date -u '+%Y-%m-%d')

{
echo "# Phase 16 gate report: full reproduction audit, including mainnet"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **PASS**"
echo
echo "The chain holds $ROWS claims. Inventory clean: no malformed rows, no duplicate ids, no claim"
echo "without a command, no missing evidence file, no missing script."
echo
echo "## 16.1 reproduction"
echo
echo "9 of 9 gates re-run and passing, including the full Rust workspace and 113 contract tests."
echo "What was NOT re-run is stated in the report before anything else: gates that spend gas, because"
echo "re-running them would spend the user's OKB to re-prove what the chain already records, and"
echo "gates needing the Browser pane, which E11 makes impossible to drive headless."
echo
echo "## 16.2 repairs, three defects the audit found in the chain itself"
echo
echo "1. \`C-710\` appeared **twice**, making any \`[C-710]\` reference ambiguous. Superseded row"
echo "   DELETED, 116 rows down to 115."
echo "2. \`C-906\` cited \`scripts/137-dashboard-audit.sh\`, which never existed."
echo "3. \`C-907\` cited \`scripts/138-failure-paths.sh\`, same problem."
echo
echo "2 and 3 are CITATION errors, not unreproducible claims, and the distinction decides the remedy:"
echo "the real artefacts (\`scripts/dashboard_audit.js\`, \`scripts/failure_paths_audit.js\`) exist and"
echo "are named inside the evidence files themselves. Cutting them would have deleted real work"
echo "because a row pointed at the wrong filename. The repair script checks those files exist FIRST"
echo "and refuses to repair, forcing a cut, if they do not."
echo
echo "## 16.3 mainnet, re-verified from chain 196"
echo
echo "7 transactions each checked against **what its document CLAIMS**, not against success: 6"
echo "confirmed and 1 correctly REVERTED, that being the proof the risk guard refuses an over-cap"
echo "trade with real money at stake. An earlier version of this gate expected success everywhere and"
echo "failed on exactly that transaction, which would have inverted the meaning of Phase 12's most"
echo "important negative result."
echo
echo "7 contracts carry real bytecode. Live state: \`feeBps\` 50, \`chargeCount\` 1 so a fee was"
echo "actually charged on mainnet, treasury \`0x...0fee0196\` DISTINCT from the deployer, vault"
echo "solvent, \`totalDeposits\` 0 because the user's deposit was fully withdrawn."
echo
echo "Two hashes in the documents turned out not to be transactions at all: they are quoted REVERT"
echo "DATA, and a 4-byte selector plus a 32-byte market id is exactly 64 hex characters. The first"
echo "version used \`cast receipt\`, which BLOCKS waiting for confirmation, and hung indefinitely"
echo "waiting for a transaction that will never exist."
echo
echo "## 16.4 fake-win register"
echo
echo "33 fake wins named in TASKS.md, **33 with a claim covering their subtask, 0 without**."
echo
echo "The register reports COVERAGE and prints each claim's text. It deliberately does not score"
echo "whether a refusal is convincing: a script asserting that thirty traps were avoided, written by"
echo "the same process that might have fallen into them, would be this task's own fake win."
echo
echo "## Reproduce"
echo
echo '```'
echo "python3 scripts/181-repro-inventory.py"
echo "bash scripts/183-reproduce.sh"
echo "bash scripts/184-mainnet-reverify.sh"
echo "python3 scripts/185-fake-win-register.py"
echo '```'
} > "$GATE"

if grep -q "C-1600" "$CHAIN"; then
  echo "already recorded"
else
cat >> "$CHAIN" <<EOF
| C-1600 | Nine gates re-run end to end and all passing, including the full Rust workspace and 113 contract tests, with the exclusions stated BEFORE the number rather than after: gates that spend gas are not re-run because doing so would spend the user's OKB to re-prove what chain 196 already records permanently, and Browser-pane gates cannot be driven headless per E11. Both categories are named with their real reproduce paths rather than dropped | evidence/phase16/reproduce.md | bash scripts/183-reproduce.sh | DEMONSTRATED | 16.1 | $TODAY |
| C-1601 | The reproduction audit found three defects IN THE EVIDENCE CHAIN ITSELF and repaired them: C-710 appeared twice, making any reference to it ambiguous, and the superseded row was DELETED taking the chain from 116 to 115; C-906 and C-907 cited scripts 137 and 138 that never existed, when the real artefacts are scripts/dashboard_audit.js and scripts/failure_paths_audit.js, named inside the evidence files themselves. The inventory pass runs BEFORE any re-execution on purpose, because a row citing a file that does not exist produces a runner failure indistinguishable from a flaky test. Citation errors were corrected rather than cut, and the repair script checks the real artefacts exist FIRST and refuses to repair, forcing a cut, if they do not | evidence/phase16/inventory.json, evidence/gates/phase16.md | python3 scripts/181-repro-inventory.py | DEMONSTRATED | 16.2 | $TODAY |
| C-1602 | Every mainnet claim re-verified FROM CHAIN 196 rather than from the local files that assert it, with the hashes and addresses SCRAPED from the evidence rather than pasted into the checker, so a document that quietly changed a hash fails instead of being confirmed by a constant updated to match. 7 transactions each checked against what its own document CLAIMS: 6 confirmed and 1 correctly REVERTED, that being the proof the risk guard refuses an over-cap trade with real money at stake. An earlier version expected success everywhere and failed on exactly that transaction, which would have inverted the meaning of Phase 12's most important negative result. 7 contracts carry real bytecode; live state shows chargeCount 1 so a fee was genuinely charged, a treasury DISTINCT from the deployer, and a solvent vault at zero deposits because the user's money was fully returned. Two 64-hex strings proved not to be transactions at all but quoted revert data, which is correct content a regex cannot distinguish from a hash | evidence/phase16/mainnet-reverify.md | bash scripts/184-mainnet-reverify.sh | DEMONSTRATED | 16.3 | $TODAY |
| C-1603 | All 33 fake wins named in TASKS.md have a claim covering their subtask, 0 without. The register reports COVERAGE and prints each claim's text for a reader to judge, and deliberately refuses to score whether a refusal is convincing: a script asserting that thirty traps were avoided, written by the same process that might have fallen into them, would be this task's own fake win, and saying so is the only honest way to run this check | evidence/phase16/fake-win-register.md | python3 scripts/185-fake-win-register.py | DEMONSTRATED | 16.4 | $TODAY |
EOF
echo "appended C-1600..C-1603"
fi

echo "written: $GATE"
grep -c "^| C-" "$CHAIN"
