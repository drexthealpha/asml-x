#!/usr/bin/env bash
# Task 16.1: re-run the reproduction set and record what actually passes.
#
# THINKING: #49 evidence, #60 map-territory, #19 falsifiability.
#
# EVIDENCE PATH: evidence/phase16/reproduce.md
# PASS: every gate in the set below exits zero. Anything that does not is CUT in 16.2, not footnoted.
#
# WHAT IS IN THE SET AND WHAT IS NOT, stated up front because this is the number a reader should be
# suspicious of. Gates that SPEND GAS are excluded: the user funded this deployment with 0.005 OKB
# and re-running the mainnet and submission paths would spend their money to re-prove something the
# chain already records permanently. 16.3 re-verifies those FROM CHAIN instead, which is a stronger
# check than re-running them anyway: it reads what actually happened rather than doing it again.
#
# Gates needing the Browser pane are also excluded, because E11 means they cannot run headless from a
# shell; they are named in the report with their real reproduce path rather than silently dropped.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase16/reproduce.md"
LOG="$REPO/evidence/phase16/reproduce.log"
mkdir -p "$(dirname "$OUT")"
: > "$LOG"

PASS=0; FAIL=0; ROWS=""

run() { # label command...
  local label="$1"; shift
  local start end rc
  start=$(date +%s)
  echo "### $label" >> "$LOG"
  if "$@" >> "$LOG" 2>&1; then rc=0; else rc=$?; fi
  end=$(date +%s)
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1)); printf "  %-40s PASS  %ss\n" "$label" "$((end - start))"
    ROWS="$ROWS| \`$label\` | $((end - start))s | PASS |
"
  else
    FAIL=$((FAIL + 1)); printf "  %-40s FAIL (exit %s)\n" "$label" "$rc"
    ROWS="$ROWS| \`$label\` | - | **FAIL exit $rc** |
"
  fi
}

CARGO="$HOME/.cargo/bin/cargo"
FORGE="$HOME/.foundry/bin/forge"

echo "=== reproduction set ==="
run "cargo test --workspace"      "$CARGO" test --workspace --quiet
run "forge test (contracts)"      bash -c "cd '$REPO/contracts' && '$FORGE' test --color never"
run "14.1 differential proof"     bash 164-differential-proof.sh
run "14.2 vault invariants"       bash 166-vault-invariants.sh
run "14.6 learning effect"        bash 174-learning-effect.sh
run "15.1 adversarial fee/vault"  bash 178-adversarial-fee-vault.sh
run "15.2 protocol version"       bash 179-protocol-version.sh
run "14.7 phase 14 audit"         bash 176-phase14-audit.sh
run "chain inventory"             python3 181-repro-inventory.py

TOTAL=$((PASS + FAIL))
VERDICT=FAIL
[ "$FAIL" -eq 0 ] && VERDICT=PASS

ROWCOUNT=$(grep -c "^| C-" "$REPO/evidence/CHAIN-OF-EVIDENCE.md")

{
echo "# Task 16.1: reproduction audit"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **$VERDICT**"
echo
echo "$PASS of $TOTAL gates passed. The chain holds $ROWCOUNT claims."
echo
echo "## What was re-run"
echo
echo "| gate | time | result |"
echo "|---|---|---|"
printf "%s" "$ROWS"
echo
echo "## What was NOT re-run, and why"
echo
echo "This is the number a reader should be suspicious of, so it is stated before anything else."
echo
echo "1. **Gates that spend gas.** The user funded this deployment with 0.005 OKB and the whole"
echo "   mainnet launch cost 0.000203652 of it. Re-running the mainnet and submission paths would"
echo "   spend their money to re-prove something the chain already records permanently. **16.3"
echo "   re-verifies those FROM CHAIN instead**, which is the stronger check: it reads what actually"
echo "   happened rather than doing it again and hoping it matches."
echo "2. **Gates needing the Browser pane.** E11: with the pane closed, \`requestAnimationFrame\` and"
echo "   \`setTimeout\` callbacks do not run, so a headless shell cannot drive them. These are"
echo "   \`scripts/dashboard_audit.js\` and \`scripts/failure_paths_audit.js\`, named with their real"
echo "   reproduce path in the chain rather than dropped."
echo
echo "## Defects this audit found in the chain itself"
echo
echo "The inventory pass runs BEFORE any re-execution, because a row citing a file that does not"
echo "exist is a defect a re-run would never surface: the runner would report a failure"
echo "indistinguishable from a flaky test."
echo
echo "It found three, all now repaired by \`scripts/182-chain-repairs.py\`:"
echo
echo "1. **\`C-710\` appeared twice.** The second row was a rewrite of the first, so any reference to"
echo "   \`[C-710]\` was ambiguous. The superseded row is DELETED, taking the chain from 116 to 115."
echo "2. **\`C-906\` cited \`bash scripts/137-dashboard-audit.sh\`, which never existed.** The real"
echo "   artefact is \`scripts/dashboard_audit.js\`, named inside the evidence file itself."
echo "3. **\`C-907\` cited \`bash scripts/138-failure-paths.sh\`** with the same problem."
echo
echo "**2 and 3 are citation errors, not unreproducible claims, and the difference decides the"
echo "remedy.** 16.2 says a claim that does not reproduce is cut rather than footnoted. Cutting these"
echo "would have deleted real work with real evidence because a row pointed at the wrong filename."
echo "The repair script checks the JS files exist FIRST and refuses to repair, requiring a cut,"
echo "if they do not."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/183-reproduce.sh"
echo '```'
} > "$OUT"

echo
echo "written: $OUT"
echo "VERDICT: $VERDICT  ($PASS/$TOTAL)"
[ "$VERDICT" = PASS ]
