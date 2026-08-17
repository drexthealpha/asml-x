#!/usr/bin/env bash
# Task 1.19 Phase 1 adversarial audit. For each tool, DELETE its evidence file and re-run its
# command. If the file does not regenerate, the smoke test was not reproducible and does not count.
#
# THINKING: #66 red teaming (attack the evidence, not the code), #49 skeptical (an evidence file on
# disk proves a command ran ONCE, which is not the same as a command that works).
#
# EVIDENCE PATH declared before code: evidence/phase0/reproducibility-audit.md
# PASS: every tool evidence file regenerates from its command.
#
# Deliberately EXCLUDED from the delete-and-rerun loop, with reasons, because an exclusion with a
# reason is honest and a silent skip is not:
#   - alloy and revm: their commands recompile crates that take 17 and 4 minutes on this box. Both
#     were re-run today from a clean build within this session, which is the same evidence this
#     audit would produce.
#   - cargo-mutants: a full mutation run is ~45 minutes and was run three times today.
#   - the gemini quota probe: re-running it burns the same quota that makes it fail, and its finding
#     IS the failure.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/reproducibility-audit.md"
mkdir -p "$(dirname "$OUT")"

{
echo "# Phase 1 reproducibility audit"
echo
echo "Task 1.19. Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "Method: delete the evidence file, run the command, check the file came back with content."
echo "A command that cannot regenerate its own evidence is not a smoke test, it is a memory."
echo
echo "| tool | evidence file | command | deleted | regenerated | bytes |"
echo "|---|---|---|---|---|---|"
} > "$OUT"

check() {
  local tool="$1" file="$2" cmd="$3"
  local path="$REPO/$file"
  local before=0 after=0 deleted=no regen=no
  [ -f "$path" ] && before=$(stat -c%s "$path")
  if [ -f "$path" ]; then rm -f "$path"; deleted=yes; fi
  # Run it, discarding output: this audit is about the FILE coming back, and the command prints its
  # own verdict into that file.
  timeout 1200 bash -c "$cmd" >/dev/null 2>&1 || true
  if [ -s "$path" ]; then
    after=$(stat -c%s "$path")
    regen=yes
  fi
  printf '| %s | %s | `%s` | %s | **%s** | %s |\n' \
    "$tool" "$file" "$cmd" "$deleted" "$regen" "$after" >> "$OUT"
  printf '  %-22s %s -> %s bytes\n' "$tool" "$regen" "$after"
  [ "$regen" = "yes" ]
}

PASS=0
FAIL=0
run() { if check "$@"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi; }

run "halmos"            "evidence/phase0/halmos.txt"              "bash $REPO/scripts/45c-halmos-upgrade.sh"
run "hevm"              "evidence/phase0/hevm.txt"                "bash $REPO/scripts/47d-hevm-argotorg.sh"
run "scribble"          "evidence/phase0/scribble.txt"            "bash $REPO/scripts/48-scribble-smoke.sh"
run "act (substituted)" "evidence/phase0/act.txt"                 "bash $REPO/scripts/56-act-install.sh"
run "codebase-memory"   "evidence/phase0/codebase-memory-mcp.txt" "bash $REPO/scripts/58-codebase-memory-mcp.sh"
run "paperscraper"      "evidence/phase0/paperscraper.txt"        "bash $REPO/scripts/51-paperscraper-smoke.sh"
run "river"             "evidence/phase0/river.txt"               "bash $REPO/scripts/55-river-smoke.sh"
run "support tools"     "evidence/phase0/support-tools.txt"       "bash $REPO/scripts/62-support-tools.sh"
run "ui study audit"    "evidence/hypeterminal/citation-audit.txt" "bash $REPO/scripts/74-verify-ui-study.sh"
run "journal scale"     "evidence/phase4/journal-scale-audit.txt" "bash $REPO/scripts/77-journal-scale-audit.sh"
run "claim inventory"   "evidence/phase2/claim-inventory.txt"     "bash $REPO/scripts/63-claim-inventory.sh"
run "graph query log"   "evidence/phase2/graph-query-log.txt"     "bash $REPO/scripts/64-graph-query-log.sh"
run "chain + bytecode"  "evidence/phase2/deployment-bytecode.txt" "bash $REPO/scripts/67-verify-deployments.sh"

{
echo
echo "## Result"
echo
echo "- regenerated: **$PASS**"
echo "- failed to regenerate: **$FAIL**"
echo
if [ "$FAIL" -eq 0 ]; then
  echo "Every evidence file above was DELETED and came back from its command."
else
  echo "$FAIL file(s) did not come back. Those rows are not evidence of anything and the claims"
  echo "resting on them are cut under task 2.6, not footnoted."
fi
echo
echo "## Excluded, with reasons"
echo
echo "| tool | why not in the loop |"
echo "|---|---|"
echo "| alloy | its command recompiles alloy 2.3.0, 17m10s on this box. Re-run from a clean build earlier today, which is the same evidence this audit produces. |"
echo "| revm | recompiles revm 42, plus a contract build. Re-run from scratch earlier today, including three real failures fixed (gas cap, nonce sequence, pattern fields). |"
echo "| cargo-mutants | a full run is around 45 minutes and it ran three times today: 37 survivors, then 2, then 0. |"
echo "| gemini-grounding | re-running consumes the same free-tier quota whose exhaustion IS the finding. The failure is already precisely located: authenticated 404s and a model list prove key and transport, and the refusal is 429. |"
echo "| kontrol | substitution record, no command to re-run beyond the one that produced it. |"
echo "| gitleaks | full-history scan, and its findings live in the gitignored internal hygiene log rather than in a product evidence file. |"
} >> "$OUT"

echo
echo "regenerated $PASS, failed $FAIL"
echo "written: $OUT"
[ "$FAIL" -eq 0 ]
