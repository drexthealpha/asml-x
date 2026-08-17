#!/usr/bin/env bash
# Prove the gitleaks allowlist did not blind the gate.
#
# .gitleaks.toml allowlists anvil's published key, the public demo API keys and a contract address.
# An allowlist is exactly how a secret gate gets quietly disabled, so the only thing that settles it
# is planting a real-shaped secret and requiring the scan to fail.
#
# EVIDENCE PATH: evidence/phase18/gitleaks-mutation.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

# RESOLVED FROM PATH, with the local install as a fallback. This was hardcoded to
# "$HOME/.local/bin/gitleaks", which exists on the development machine and nowhere else. In CI the
# binary is installed to /usr/local/bin, so every invocation exited 127 (command not found) and the
# script reported "baseline=127 mutated=127 restored=127": three identical non-zero codes, which is
# the signature of a missing binary rather than a real result.
G="$(command -v gitleaks 2>/dev/null || echo "$HOME/.local/bin/gitleaks")"
if [ ! -x "$G" ]; then
  echo "gitleaks not found on PATH or at $HOME/.local/bin/gitleaks"
  exit 1
fi
OUT="$REPO/evidence/phase18/gitleaks-mutation.txt"
CANARY="$REPO/scripts/.canary-do-not-commit.sh"
mkdir -p "$(dirname "$OUT")"

cleanup() { rm -f "$CANARY"; }
trap cleanup EXIT INT TERM

{
echo "gitleaks allowlist, mutation proof"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

echo "=== baseline: clean tree ==="
"$G" detect --source . --no-git --config .gitleaks.toml --no-banner --redact --exit-code 1 > /dev/null 2>&1
BASE=$?
echo "  exit $BASE  ($([ $BASE -eq 0 ] && echo clean || echo "findings"))"

echo
echo "=== planting a real-shaped secret in a tracked path ==="
# ASSEMBLED AT RUNTIME, never written literally in this file.
#
# The first version embedded the canary in a heredoc, so gitleaks found it in THIS SCRIPT and the
# baseline scan failed before anything was planted. A test whose own source trips the thing it is
# testing cannot measure it. Split into fragments that match no rule until joined.
# GENERATED RANDOMLY, so no key-shaped literal exists in this file at all. Splitting a hex constant
# into fragments was not enough: a 32-character hex half still matched `generic-api-key`, and the
# baseline scan kept failing on this script rather than on the tree it was meant to measure.
#
# A freshly random 32-byte key is also a stronger canary than a well-known example value, since it
# cannot have been allowlisted anywhere by accident.
RANDOM_PK="0x$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
AKIA_PREFIX="A""K""I""A"
{
  echo "#!/usr/bin/env bash"
  echo "AWS_ACCESS_KEY_ID=${AKIA_PREFIX}IOSFODNN7EXAMPLE"
  echo "PRIVATE_KEY=${RANDOM_PK}"
} > "$CANARY"
echo "  wrote $CANARY with a freshly generated key"

"$G" detect --source . --no-git --config .gitleaks.toml --no-banner --redact --exit-code 1 > /tmp/gl-canary.txt 2>&1
MUT=$?
echo "  exit $MUT  ($([ $MUT -ne 0 ] && echo "CAUGHT" || echo "MISSED"))"
grep -E "Finding|RuleID|File" /tmp/gl-canary.txt | head -8 | sed 's/^/    /'

rm -f "$CANARY"
echo
echo "=== restored ==="
"$G" detect --source . --no-git --config .gitleaks.toml --no-banner --redact --exit-code 1 > /dev/null 2>&1
RES=$?
echo "  exit $RES  ($([ $RES -eq 0 ] && echo clean || echo "findings"))"

echo
if [ "$BASE" -eq 0 ] && [ "$MUT" -ne 0 ] && [ "$RES" -eq 0 ]; then
  echo "VERDICT: PASS  the allowlist permits the published test values and still catches a real secret."
else
  echo "VERDICT: FAIL  baseline=$BASE mutated=$MUT restored=$RES"
fi
} 2>&1 | tee "$OUT"

grep -q "VERDICT: PASS" "$OUT"
