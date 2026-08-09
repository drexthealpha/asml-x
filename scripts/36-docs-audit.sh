#!/usr/bin/env bash
# Phase 9 R5 sweep: check the numbers the docs claim against what the repo actually does.
# A README with a wrong count is an unbacked claim, which is the thing this project's rules
# exist to prevent.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$HOME/.foundry/bin:$PATH"
cd "$REPO"

OUT="$REPO/evidence/docs-audit.md"
FAILED=0

note() { echo "$1"; echo "$1" >> "$OUT"; }
check() { # label claimed actual
  if [ "$2" = "$3" ]; then
    note "| $1 | $2 | $3 | MATCH |"
  else
    note "| $1 | $2 | $3 | **MISMATCH** |"
    FAILED=$((FAILED+1))
  fi
}

{
  echo "# Docs audit"
  echo
  echo "R5 sweep, captured $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
  echo
  echo "| claim | documented | measured | result |"
  echo "|---|---|---|---|"
} > "$OUT"

echo "=== measuring ==="
RUST_SUITES=$(cargo test --workspace 2>&1 | grep -c "test result: ok")
FORGE_TESTS=$(cd contracts && forge test 2>&1 | grep -oE "[0-9]+ tests passed" | tail -1 | awk '{print $1}')
if [ -z "$FORGE_TESTS" ]; then
  FORGE_TESTS=$(cd contracts && forge test 2>&1 | grep -oE "Ran [0-9]+ test suites.*: [0-9]+ tests passed" | grep -oE "[0-9]+ tests passed" | awk '{print $1}')
fi

check "rust test suites green" "19" "$RUST_SUITES"
# 50, not 49. The first run of this audit caught the docs claiming 49 after the crossed-book
# tests were added, which is exactly the unbacked claim this script exists to find.
check "foundry tests passing" "50" "${FORGE_TESTS:-unknown}"

echo
echo "=== mutation tables ==="
for f in mutation-risk-engine mutation-contracts mutation-rwa mutation-learning; do
  if [ -f "evidence/$f.md" ]; then
    # No `|| echo 0`: grep -c already PRINTS 0 when there are no matches and then exits
    # non-zero, so the fallback appended a second zero and every comparison against "0"
    # failed. That produced ten false mismatches on the first run of this audit.
    RED=$(grep -c "RED, test holds" "evidence/$f.md")
    GAP=$(grep -c "STAYED GREEN" "evidence/$f.md")
    SED=$(grep -c "sed did not apply" "evidence/$f.md")
    note "| $f | claimed all RED | $RED RED, $GAP gaps, $SED inapplicable | $([ "$GAP" = "0" ] && [ "$SED" = "0" ] && echo CLEAN || echo '**NOT CLEAN**') |"
    if [ "$GAP" != "0" ] || [ "$SED" != "0" ]; then FAILED=$((FAILED+1)); fi
  else
    note "| $f | claimed to exist | MISSING FILE | **MISMATCH** |"
    FAILED=$((FAILED+1))
  fi
done

echo
echo "=== deployed addresses in README match deployments.json ==="
python3 - >> "$OUT" <<'PY'
import json, re, sys
dep = json.load(open('deployments.json'))
readme = open('README.md').read()
bad = 0
for key in ['venue', 'riskGuard', 'batchExecutor', 'rwaVault', 'rwaRiskGuard']:
    addr = dep.get(key)
    if not addr:
        print(f"| README {key} | expected an address | missing from deployments.json | **MISMATCH** |")
        bad += 1
        continue
    if addr.lower() in readme.lower():
        print(f"| README {key} | {addr[:12]}... | present | MATCH |")
    else:
        print(f"| README {key} | {addr[:12]}... | NOT IN README | **MISMATCH** |")
        bad += 1
open('/tmp/addr_bad', 'w').write(str(bad))
PY
ADDR_BAD=$(cat /tmp/addr_bad 2>/dev/null || echo 0)
FAILED=$((FAILED + ADDR_BAD))

echo
echo "=== evidence files referenced by the docs actually exist ==="
python3 - >> "$OUT" <<'PY'
import os, re, glob
missing = 0
docs = ['README.md', 'JUDGE-GUIDE.md', 'docs/limitations.md', 'docs/mainnet-path.md']
refs = set()
for d in docs:
    if not os.path.exists(d):
        continue
    for m in re.finditer(r'\(([A-Za-z0-9_\-./]+\.(?:md|txt|json|jsonl|sol|rs|html))\)', open(d).read()):
        p = m.group(1)
        base = os.path.dirname(d)
        cand = os.path.normpath(os.path.join(base, p)) if not p.startswith('docs/') or base == '' else os.path.normpath(p)
        refs.add((d, p, cand))
for d, p, cand in sorted(refs):
    if os.path.exists(cand) or os.path.exists(p):
        continue
    print(f"| {d} links {p} | expected to exist | MISSING | **MISMATCH** |")
    missing += 1
open('/tmp/ref_missing', 'w').write(str(missing))
if missing == 0:
    print("| all doc file links | resolve | resolve | MATCH |")
PY
REF_BAD=$(cat /tmp/ref_missing 2>/dev/null || echo 0)
FAILED=$((FAILED + REF_BAD))

echo
echo "=== style sweep: forbidden constructions in judge-facing docs ==="
STYLE=0
for f in README.md JUDGE-GUIDE.md docs/limitations.md docs/mainnet-path.md; do
  EM=$(grep -c "—" "$f" 2>/dev/null)
  if [ "$EM" != "0" ]; then
    note "| $f | no em dashes | $EM found | **MISMATCH** |"
    STYLE=$((STYLE+1))
  fi
done
[ "$STYLE" = "0" ] && note "| judge-facing docs | no em dashes | none found | MATCH |"
FAILED=$((FAILED + STYLE))

echo
echo "=== unlabelled claim sweep ==="
UNTAGGED=$(grep -ncE "DEMONSTRATED|INFERRED" README.md | cut -d: -f1)
note "| README evidence labels | present | $UNTAGGED lines carry a label | INFO |"

{
  echo
  echo "## Result"
  echo
  if [ "$FAILED" = "0" ]; then
    echo "All checked claims match. $FAILED mismatches."
  else
    echo "**$FAILED mismatch(es).** Each one is an unbacked claim and must be fixed."
  fi
} >> "$OUT"

echo
echo "mismatches: $FAILED"
echo "written: $OUT"
exit 0
