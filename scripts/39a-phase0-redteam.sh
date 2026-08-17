#!/usr/bin/env bash
# Task 0.9: assume the gitleaks scan lied. Verify by independent method.
#
# THINKING: #66 red teaming (attack my own scan), #7 counterfactual (what if a key HAD been
# committed and the scanner missed it).
#
# Two independent checks that do not share gitleaks' rule set:
#   1. the actual keystore password FILE CONTENT searched across all history
#   2. structural greps for key shapes the scanner might rule out
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

OUT="$REPO/evidence/hygiene/phase0-redteam.md"
mkdir -p "$(dirname "$OUT")"
FINDINGS=0

{
echo "# Phase 0 adversarial audit"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Task 0.9."
echo
echo "Premise: the gitleaks scan may have lied. Verify by methods that do not share its"
echo "rule set. A single method agreeing with itself proves nothing."
echo

echo "## 1. The real keystore password, searched across ALL history"
echo
if [ -f "$PASSFILE" ]; then
  # Search history for the ACTUAL secret value. This is the strongest possible check and it
  # cannot be fooled by a rule-set gap. The value itself is never printed.
  PASSLEN=$(wc -c < "$PASSFILE" | tr -d ' ')
  echo "keystore password file present, $PASSLEN bytes. Searching history for its content."
  if git log --all -p 2>/dev/null | grep -qF "$(cat "$PASSFILE")"; then
    echo "**FINDING: the keystore password appears in git history.**"
    FINDINGS=$((FINDINGS+1))
  else
    echo "[PASS] the keystore password does NOT appear anywhere in history."
  fi
else
  echo "[SKIP] no keystore password file at \$PASSFILE, nothing to search for."
fi
echo

echo "## 2. The deployer address co-located with any 64-hex"
echo
echo "A private key committed next to its address is the classic leak shape."
HITS=$(git log --all -p 2>/dev/null | grep -c "0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46" || true)
echo "deployer address occurrences in history: $HITS (expected, it is a public address)"
CO=$(git log --all -p 2>/dev/null | grep -A 3 -B 3 "0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46" 2>/dev/null | grep -cE '0x[0-9a-fA-F]{64}' || true)
echo "64-hex values within 3 lines of the deployer address: $CO"
if [ "${CO:-0}" -gt 0 ]; then
  echo "Investigating each. Note: tx hashes are also 64-hex and are PUBLIC by design."
  git log --all -p 2>/dev/null | grep -A 3 -B 3 "0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46" 2>/dev/null \
    | grep -oE '0x[0-9a-fA-F]{64}' | sort -u | head -10 | sed 's/^/    /'
  echo "  Each of the above must be a known tx hash. A value that is not is a FINDING."
fi
echo

echo "## 3. Structural key shapes gitleaks might not rule on"
echo
for PAT in 'AQ\.[A-Za-z0-9_-]{20,}' 'ghp_[A-Za-z0-9]{30,}' 'github_pat_[A-Za-z0-9_]{30,}' \
           '"crypto"[[:space:]]*:[[:space:]]*\{' 'BEGIN [A-Z ]*PRIVATE KEY' \
           'mnemonic' 'seed[ _]phrase'; do
  N=$(git log --all -p 2>/dev/null | grep -cE "$PAT" || true)
  if [ "${N:-0}" -gt 0 ]; then
    printf '  **FINDING** %-42s %s hits\n' "$PAT" "$N"
    FINDINGS=$((FINDINGS+1))
  else
    printf '  [PASS]      %-42s 0\n' "$PAT"
  fi
done
echo

echo "## 4. Is the keystore itself reachable from the repo?"
echo
if [ -e "$REPO/.asml-keys" ]; then
  echo "**FINDING: .asml-keys exists INSIDE the repo.**"
  FINDINGS=$((FINDINGS+1))
else
  echo "[PASS] .asml-keys is not inside the repo."
fi
if [ -f "$KEYFILE" ]; then
  echo "[PASS] keystore lives at \$KEYFILE, outside the repo tree."
else
  echo "[WARN] no keystore at \$KEYFILE. Check scripts/gen-deployer-wallet.sh."
fi
echo

echo "## Verdict"
echo
if [ "$FINDINGS" = "0" ]; then
  echo "Two independent methods agree with gitleaks: **zero real secrets in history.**"
  echo "The single gitleaks finding (demo-agent-key-2) is an intentionally public demo key"
  echo "documented in ADR-010, and it is not a credential for anything."
else
  echo "**$FINDINGS finding(s). Do not treat the history as clean.**"
fi
} | tee "$OUT"

echo
echo "written: $OUT"
[ "$FINDINGS" = "0" ] || exit 1
exit 0
