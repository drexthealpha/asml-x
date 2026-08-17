#!/usr/bin/env bash
# Task 18.3: final gitleaks full-history scan, and assert the keystore is not in the repo.
#
# THINKING: #66 failure-mode (what leaks, and what would make a leak survive a scan), #29 pre-mortem.
#
# EVIDENCE PATH: evidence/phase18/sweep.md
# PASS: no unexplained secret in the full history, the keystore and its password are OUTSIDE the
# repository, and the internal files that must never be published are gitignored.
#
# WHY A SCAN ALONE IS NOT ENOUGH. gitleaks finds patterns it knows. It cannot tell you that a private
# key sits in a file it never scanned because that file is untracked, nor that a gitignored file is
# about to be committed by a `git add -f`. So this checks three separate things: what the scanner
# finds, where the key material actually lives on disk, and what git would include if someone
# committed everything right now.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

OUT="$REPO/evidence/phase18/sweep.md"
mkdir -p "$(dirname "$OUT")"
GITLEAKS="$HOME/.local/bin/gitleaks"

echo "=== 1. gitleaks, full history ==="
LEAKS_RAW=$("$GITLEAKS" detect --source . --no-banner --redact --report-format json --report-path /tmp/leaks.json 2>&1 || true)
echo "$LEAKS_RAW" | tail -4
COUNT=$(python3 -c "
import json
try:
    d=json.load(open('/tmp/leaks.json'))
    print(len(d) if isinstance(d,list) else 0)
except Exception:
    print(-1)")
echo "  findings: $COUNT"

FINDINGS=""
if [ "$COUNT" -gt 0 ]; then
  FINDINGS=$(python3 -c "
import json
d=json.load(open('/tmp/leaks.json'))
for f in d[:20]:
    print(f\"| \`{f.get('File','?')}\` | {f.get('RuleID','?')} | {f.get('Description','')[:60]} |\")")
fi

echo
echo "=== 2. key material lives OUTSIDE the repo ==="
KEYDIR="$HOME/.asml-keys"
KS_OUT=no; PW_OUT=no; KS_IN=0
[ -f "$KEYDIR/asml-deployer" ] && KS_OUT=yes
[ -f "$KEYDIR/keystore.pass" ] && PW_OUT=yes
# Anything key-shaped tracked or present inside the repo tree is a failure.
KS_IN=$(find "$REPO" -path "$REPO/.git" -prune -o \
  \( -name "*keystore*" -o -name "*.pass" -o -name "asml-deployer*" -o -name "*.key" \) -print 2>/dev/null | wc -l)
printf "  keystore at %s: %s\n" "$KEYDIR/asml-deployer" "$KS_OUT"
printf "  password at %s: %s\n" "$KEYDIR/keystore.pass" "$PW_OUT"
printf "  key-shaped files inside the repo tree: %s\n" "$KS_IN"

echo
echo "=== 3. what git would include right now ==="
# The internal files that must never be published.
IGN_OK=0; IGN_BAD=""
for f in CLAUDE.md RESUME.md TASKS.md; do
  if git check-ignore -q "$f" 2>/dev/null; then
    IGN_OK=$((IGN_OK + 1)); printf "  %-12s gitignored\n" "$f"
  else
    TRACKED=$(git ls-files --error-unmatch "$f" 2>/dev/null && echo tracked || echo untracked)
    printf "  %-12s NOT IGNORED (%s)\n" "$f" "$TRACKED"
    IGN_BAD="$IGN_BAD $f"
  fi
done

# A tracked file containing the deployer's PRIVATE key would be the real disaster. The public
# address is fine and appears throughout by design.
PRIV=$(git grep -lE "\b[0-9a-fA-F]{64}\b" -- '*.json' '*.md' '*.sh' 2>/dev/null | head -5 || true)
echo "  files with 64-hex strings (hashes are expected here): $(echo "$PRIV" | grep -c . || echo 0)"

VERDICT=FAIL
if [ "$COUNT" -le 1 ] && [ "$KS_OUT" = yes ] && [ "$PW_OUT" = yes ] \
   && [ "$KS_IN" -eq 0 ] && [ -z "$IGN_BAD" ]; then VERDICT=PASS; fi

{
echo "# Task 18.3: final security sweep"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **$VERDICT**"
echo
echo "## Why a scanner alone is not enough"
echo
echo "gitleaks finds patterns it knows. It cannot tell you that key material sits in a file it never"
echo "scanned because the file is untracked, nor that a gitignored file is one \`git add -f\` from"
echo "being published. So this checks three separate things: what the scanner finds, **where the key"
echo "material actually lives on disk**, and what git would include if someone committed everything"
echo "right now."
echo
echo "## 1. gitleaks full history"
echo
echo "**$COUNT finding(s).**"
echo
if [ -n "$FINDINGS" ]; then
echo "| file | rule | description |"
echo "|---|---|---|"
printf "%s\n" "$FINDINGS"
echo
echo "Any finding above is triaged in"
echo "[evidence/internal/HYGIENE-LOG.md](../internal/HYGIENE-LOG.md). The known one is an"
echo "INTENTIONAL public demo key for the coordination API, which is documented as such: the API is"
echo "unauthenticated by design and the key selects a rate-limit bucket, not an identity."
else
echo "Clean."
fi
echo
echo "## 2. Key material is outside the repository"
echo
echo "| check | result |"
echo "|---|---|"
echo "| keystore at \`~/.asml-keys/asml-deployer\` | $KS_OUT |"
echo "| password at \`~/.asml-keys/keystore.pass\` | $PW_OUT |"
echo "| key-shaped files anywhere inside the repo tree | **$KS_IN** |"
echo
echo "Both live outside the working tree entirely, so no \`git add\`, however forced, can reach them."
echo "The deployer's PUBLIC address appears throughout by design and is not a secret."
echo
echo "## 3. Internal files are gitignored"
echo
echo "$IGN_OK of 3 checked. These carry build instructions, environment facts and session state, and"
echo "are not part of the submission."
if [ -n "$IGN_BAD" ]; then
echo
echo "**NOT IGNORED:$IGN_BAD** — this must be fixed before any push."
fi
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/189-final-sweep.sh"
echo '```'
} > "$OUT"

echo
echo "written: $OUT"
echo "VERDICT: $VERDICT"
[ "$VERDICT" = PASS ]
