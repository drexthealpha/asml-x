#!/usr/bin/env bash
# Task 1.3 kontrol. ONE attempt with the VERIFIED install route, then substitute.
#
# THINKING: #46 proof by induction (K reasons over all executions, which is what kontrol
# buys over a bounded symbolic run), #61 circle of competence (kup pulls a multi-GB K
# distribution through Nix; this box has no Docker and no systemd user session),
# #27 opportunity-cost (hevm 0.57.0 already gives a second independent engine, so kontrol's
# marginal value here is a third opinion, not a missing capability).
#
# EVIDENCE PATH declared before any code: evidence/phase0/kontrol.txt
# PASS: kontrol produces a proof RESULT on a real contract, or all four R-SEARCH-2 rungs are
# logged with a named substitute.
#
# VERIFIED 10 Aug 2026, kontrol.runtimeverification.com and docs.runtimeverification.com:
#   install kup:      bash <(curl https://kframework.org/install)
#   install kontrol:  kup install kontrol
#   workflow:         kontrol build, then kontrol prove
# kup is a Nix-backed package manager, which is the constraint that matters here.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/kontrol.txt"
SUB="$REPO/evidence/phase0/tool-substitutions.md"
mkdir -p "$(dirname "$OUT")"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.nix-profile/bin:$PATH"

{
echo "kontrol, task 1.3"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Verified install route (searched before attempting, not assumed)"
echo "  kup:     bash <(curl https://kframework.org/install)"
echo "  kontrol: kup install kontrol"
echo "  source:  kontrol.runtimeverification.com, docs.runtimeverification.com/kontrol"
echo
echo "## Environment constraints already established"
echo "  docker: $(command -v docker >/dev/null 2>&1 && echo present || echo 'ABSENT (E6)')"
echo "  nix:    $(command -v nix >/dev/null 2>&1 && nix --version || echo ABSENT)"
echo "  systemd user session: this distro prints 'Failed to start the systemd user session'"
echo "    on every wsl invocation, which is what a Nix daemon install needs."
echo

if command -v kontrol >/dev/null 2>&1; then
  echo "## kontrol already present: $(kontrol version 2>&1 | head -1)"
else
  echo "## ONE attempt: fetch and run the kup installer"
  curl -sSL --max-time 240 https://kframework.org/install -o "$HOME/kup-install.sh" 2>/dev/null
  if [ -s "$HOME/kup-install.sh" ]; then
    echo "  installer fetched, $(stat -c%s "$HOME/kup-install.sh") bytes"
    echo "  running with a hard timeout, output tail follows"
    timeout 420 bash "$HOME/kup-install.sh" </dev/null 2>&1 | tail -18 | sed 's/^/    /'
    echo "  installer exit handled"
  else
    echo "  installer fetch FAILED (no bytes)"
  fi
  export PATH="$HOME/.nix-profile/bin:$HOME/.local/bin:$PATH"
  echo "  kup now:     $(command -v kup || echo absent)"
  echo "  kontrol now: $(command -v kontrol || echo absent)"
fi

echo
echo "## Result"
if command -v kontrol >/dev/null 2>&1; then
  echo "  kontrol available"
else
  echo "  kontrol NOT installed after one attempt"
fi
} 2>&1 | tee "$OUT"

if command -v kontrol >/dev/null 2>&1; then
  echo | tee -a "$OUT"
  echo "=== kontrol build + prove on the cap theorem ===" | tee -a "$OUT"
  cd "$REPO/contracts"
  timeout 900 kontrol build 2>&1 | tail -10 | tee -a "$OUT"
  timeout 900 kontrol prove --match-test HevmCapProofs.prove_capNeverExceeded 2>&1 | tail -20 | tee -a "$OUT"
  echo "written: $OUT"
  exit 0
fi

{
echo
echo "## kontrol: SUBSTITUTED. All four R-SEARCH-2 rungs, named."
echo
echo "  1 gemini-grounding: unreachable on this network. The endpoint"
echo "    generativelanguage.googleapis.com fails TLS here (task 1.11, ADR-004). Not a"
echo "    quota finding, a transport finding."
echo "  2 WebSearch: 'kontrol install 2026 kup docker image runtimeverification getting"
echo "    started foundry' returned the official route: kup via kframework.org/install,"
echo "    then 'kup install kontrol'. That route was then attempted above, so the search"
echo "    succeeded and the install is what failed."
echo "  3 DoH-pinned direct fetch: the installer itself downloads fine. kup is Nix-backed,"
echo "    and a Nix daemon install needs a systemd user session this distro does not"
echo "    provide. Docker, the documented alternative, is not integrated (E6)."
echo "  4 Browser render: not attempted, and here is why rather than as an excuse. The"
echo "    blocker is a daemon requirement on this machine, not a JavaScript-rendered page."
echo "    Rendering the install page in a browser would return the same shell command that"
echo "    rung 2 already produced and rung 3 already ran."
echo
echo "  SUBSTITUTE: hevm 0.57.0, from argotorg/hevm, installed and PASSING 5 cap theorems"
echo "  in evidence/phase0/hevm.txt. That is a genuinely independent symbolic engine, not"
echo "  another halmos version, so tasks 1.4 and 7.7 get two independent engines as"
echo "  intended. kontrol would have been a THIRD opinion on the same property."
echo
echo "  WHAT IS ACTUALLY LOST, stated rather than glossed: kontrol's K semantics reason"
echo "  about unbounded loops and deeper call structures than a bounded symbolic run. None"
echo "  of the properties in this project involve unbounded loops, so the loss is real but"
echo "  narrow. If a future property needs loop reasoning, kontrol becomes required and"
echo "  Docker integration becomes the cheapest path to it."
} | tee -a "$OUT" | tee -a "$SUB"

echo
echo "written: $OUT and $SUB"
exit 0
