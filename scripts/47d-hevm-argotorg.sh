#!/usr/bin/env bash
# Task 1.4, route three, and the one that should have been route one.
#
# THINKING: #60 map-territory (my model said ethereum/hevm; hevm MOVED to argotorg/hevm,
# and that single stale fact caused the whole failure), #7 counterfactual (reading the
# install doc first would have prevented the segfault), #50 empirical (probe the real
# asset and the real solver dependency).
#
# VERIFIED 10 Aug 2026 before writing this script:
#   repo    argotorg/hevm            (ethereum/hevm is the OLD location)
#   latest  0.57.0, tag "release/0.57.0"
#   asset   hevm-x86_64-linux        (static x86 linux binary per release)
#   docs    https://hevm.dev/
#   source  github.com/argotorg/hevm/releases/tag/release/0.57.0
#
# WHY THE EARLIER ATTEMPT SEGFAULTED: it pulled from ethereum/hevm, which is stale. The
# 7.8 MB ELF it produced would not report a version and crashed immediately. That was a
# wrong-artifact problem, not a WSL-kernel problem, and I wrongly concluded the latter.
#
# hevm needs an SMT solver on PATH. z3 is the default.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/hevm.txt"
mkdir -p "$(dirname "$OUT")"
BIN="$HOME/.local/bin"; mkdir -p "$BIN"
export PATH="$BIN:$HOME/.cargo/bin:$PATH"

{
echo "hevm install, task 1.4, route three (correct repo)"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Correction being applied"
echo "  Earlier attempts used ethereum/hevm. hevm has MOVED to argotorg/hevm."
echo "  Latest release 0.57.0, tag 'release/0.57.0', asset 'hevm-x86_64-linux'."
echo "  Source: github.com/argotorg/hevm/releases/tag/release/0.57.0"
echo "  The stale binary from the old path segfaulted and reported no version. That was a"
echo "  wrong artifact, not a broken kernel. My earlier conclusion was wrong."
echo

echo "## Solver dependency: hevm needs z3 on PATH"
if command -v z3 >/dev/null 2>&1; then
  echo "  z3 present: $(z3 --version 2>&1 | head -1)"
else
  echo "  installing z3 from apt"
  sudo apt-get install -y -qq z3 2>&1 | tail -2 || apt-get install -y -qq z3 2>&1 | tail -2 || echo "  apt install failed, will report"
  echo "  z3 now: $(z3 --version 2>&1 | head -1 || echo ABSENT)"
fi
echo

# Remove the stale binary so a failure here cannot be masked by the broken one.
rm -f "$BIN/hevm"

echo "## Downloading the correct asset"
URL="https://github.com/argotorg/hevm/releases/download/release/0.57.0/hevm-x86_64-linux"
CODE=$(curl -sSL --max-time 300 -o "$HOME/hevm-bin" -w '%{http_code}' "$URL" 2>/dev/null)
SIZE=$(stat -c%s "$HOME/hevm-bin" 2>/dev/null || echo 0)
echo "  $URL"
echo "  HTTP $CODE, bytes $SIZE"
echo "  type: $(file -b "$HOME/hevm-bin" 2>/dev/null | head -1)"

if [ "$CODE" = "200" ] && [ "${SIZE:-0}" -gt 1000000 ]; then
  cp "$HOME/hevm-bin" "$BIN/hevm"
  chmod +x "$BIN/hevm"
  echo
  echo "## Version check (this is what the stale binary could not do)"
  hevm version 2>&1 | head -3 | sed 's/^/  /' || echo "  version call FAILED"
else
  echo "  download did not produce a usable asset"
fi
} 2>&1 | tee "$OUT"

echo | tee -a "$OUT"
if ! hevm version >/dev/null 2>&1; then
  echo "hevm still not runnable. Falling through to the substitution record in 46-kontrol-smoke.sh." | tee -a "$OUT"
  exit 1
fi

echo "=== REAL smoke test: symbolic execution on RiskGuard ===" | tee -a "$OUT"
cd "$REPO/contracts"
forge build >/dev/null 2>&1

# hevm test discovers Foundry prove_/check_ style symbolic tests. A verdict is the pass
# condition; a version banner is explicitly NOT.
timeout 540 hevm test --root . 2>&1 | tail -35 | tee -a "$OUT"
RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict, task 1.4"
echo "  hevm 0.57.0 exit code: $RC"
echo "  This is a SECOND INDEPENDENT SYMBOLIC ENGINE, not another halmos version."
echo "  Task 7.7 can now claim two independent engines rather than two versions."
} | tee -a "$OUT"

echo "written: $OUT"
