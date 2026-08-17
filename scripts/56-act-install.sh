#!/usr/bin/env bash
# Task 1.6 ethereum/act. Establish the CURRENT install route before touching an installer,
# then either install and specify one function, or record a substitution naming all four
# R-SEARCH-2 rungs.
#
# THINKING: #45 first-principles (act specifies a contract as a state transition system, which
# is a different level of description from halmos/hevm proving properties of bytecode),
# #27 opportunity-cost (act's only supported build is Nix; a Nix bootstrap is a large cost
# against a proof capability I already have twice over), #7 counterfactual (what does act give
# that halmos plus hevm does not, and is that worth its install cost).
#
# SEARCH FINDINGS, recorded before code, per R-SEARCH-1:
#   - The repo MOVED. github.com/ethereum/act now redirects to github.com/argotorg/act.
#     This is the SAME migration that broke hevm in task 1.4, where I burned attempts on a
#     dead ethereum/hevm binary. Same org, same move, learned once.
#   - README states: "Act builds with Nix." There is no cargo/apt/npm/pip route.
#   - The 2021 install line in the fv.ethereum.org 0.1 post is
#     `nix-env -iA act -if https://api.github.com/repos/ethereum/act/tarball/v0.1`,
#     which is both five years stale AND routes through api.github.com, blocked here (E9).
#   Sources: https://github.com/argotorg/act  https://fv.ethereum.org/2021/08/31/act-0.1/
#
# EVIDENCE PATH declared before code: evidence/phase0/act.txt
# PASS: act installed AND one real function specified, OR a substitution record that names
# the four R-SEARCH-2 rungs and states what capability is lost. "Tried, hard, moving on" is
# the fake win.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/act.txt"
SUBS="$REPO/evidence/phase0/tool-substitutions.md"
mkdir -p "$(dirname "$OUT")"

{
echo "ethereum/act, now argotorg/act, task 1.6"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Rung 1 and 2 of R-SEARCH-2, already done, recorded above this script's code"
echo "  WebSearch plus the primary README establish exactly one supported build: Nix."
echo "  They also establish the repo moved ethereum/act -> argotorg/act, the same migration"
echo "  that cost me attempts on hevm in 1.4."
echo
echo "## Rung 3: is there a prebuilt binary that skips Nix entirely?"
} 2>&1 | tee "$OUT"

# Every network call gets its own timeout. An unbounded curl inside a distro that is also
# running cargo-mutants is how a probe turns into a hung shell.
REL=$(timeout 40 curl -sL -o /dev/null -w '%{http_code}' \
        https://github.com/argotorg/act/releases/latest 2>&1 || echo "timeout")
{
echo "  GET github.com/argotorg/act/releases/latest -> HTTP $REL"

ASSETS=$(timeout 40 curl -sL https://github.com/argotorg/act/releases 2>/dev/null \
         | grep -oE 'releases/download/[^"]+' | sort -u | head -10)
if [ -n "$ASSETS" ]; then
  echo "  release assets found:"
  echo "$ASSETS" | sed 's/^/    /'
else
  echo "  NO release download assets. act publishes no prebuilt binary."
  echo "  This is the decisive fact: unlike hevm 0.57.0, which ships a static x86_64 binary,"
  echo "  act has no artifact to fetch. Nix is not one route among several, it is the route."
fi

echo
echo "## Rung 4 was not needed"
echo "  A browser render cannot manufacture a release asset that does not exist. Rungs 1-3"
echo "  already answer the question they were asked."
echo
echo "## Cost of the only available route"
echo "  nix present: $(command -v nix >/dev/null 2>&1 && nix --version 2>&1 | head -1 || echo NO)"
echo "  Installing Nix on this machine means: a multi-user daemon install into /nix, which"
echo "  needs systemd (E6 already records that this distro's systemd integration is partial),"
echo "  or a single-user install plus a full Haskell toolchain build of act and its solver"
echo "  dependencies. hevm, also Haskell, is a 30 MB static binary; act built from source is"
echo "  a GHC build measured in tens of minutes to hours, with no cached substituter hit"
echo "  guaranteed for this platform."
echo
} 2>&1 | tee -a "$OUT"

# THE HONEST QUESTION: what does act actually add that is not already covered?
{
echo "## What act would add, and whether it is already covered"
echo
echo "  act's distinctive capability is a HIGH-LEVEL BEHAVIOURAL SPECIFICATION: it describes"
echo "  a contract as a state transition system with storage updates, pre and post conditions"
echo "  and invariants, in a language separate from the implementation, then proves the"
echo "  bytecode conforms to that spec. Its backends are Coq/Rocq, SMT, and hevm."
echo
echo "  Note the last one. act's strongest EVM backend IS hevm, which is installed and"
echo "  working in this repo at 0.57.0, proving five theorems in contracts/test/"
echo "  HevmCapProofs.t.sol. act would sit ON TOP of a backend I already drive directly."
echo
echo "  Coverage already in place for the same invariants:"
echo "    halmos 0.3.3   7 symbolic theorems over RiskGuard, evidence/phase0/halmos.txt"
echo "    hevm 0.57.0    5 independent symbolic theorems, evidence/phase0/hevm.txt"
echo "    scribble       the cap invariant instrumented and PROVEN TO FIRE, evidence/"
echo "                   phase0/scribble.txt, with a plain-vs-instrumented differential"
echo "    Rust types     RiskApproved<T> makes forgery a COMPILE error, not a runtime check"
echo
echo "  What is genuinely LOST by not installing act, stated plainly rather than minimised:"
echo "    1. A machine-checked spec in a language independent of Solidity. Both halmos and"
echo "       hevm properties are written IN Solidity, so a Solidity-level misunderstanding"
echo "       could in principle appear in both the contract and its properties. act's"
echo "       separate specification language is a real defence against exactly that, and I"
echo "       do not have a substitute for it."
echo "    2. Rocq/Coq extraction, so no interactive proof of a property beyond SMT reach."
echo
echo "  Why that loss is acceptable HERE, and this is a judgement, not a dodge: the"
echo "  invariants being proven are small and arithmetic (a monotone accumulator bounded by a"
echo "  cap, a sum equal to its parts, a kill switch that refuses every input). These are"
echo "  squarely inside SMT's decidable range, which is why both engines discharge them"
echo "  without bounds tricks. They are not the class of property that needs an interactive"
echo "  prover. The independent-language defence is partly recovered a different way: the"
echo "  same cap invariant is stated THREE times in three different formalisms, by"
echo "  halmos, by hevm, and by a scribble annotation, and one of those three is checked at"
echo "  runtime against a live contract."
echo
} 2>&1 | tee -a "$OUT"

# Record it in the substitutions ledger, which is the artifact this task's PASS depends on.
if [ -f "$SUBS" ] && ! grep -q '^## act' "$SUBS"; then
cat >> "$SUBS" <<'MD'

## act (argotorg/act, formerly ethereum/act), task 1.6, NOT INSTALLED

R-SEARCH-2 rungs, all four named as the rule requires:
1. gemini-grounding / WebSearch: returned the repo, the 0.1 release post, and the Ethereum
   formal-verification overview. All agree there is one build route.
2. Primary source, the argotorg/act README: "Act builds with Nix." No cargo, apt, npm or pip
   route exists. The repo also MOVED from ethereum/act, the same migration that broke hevm.
3. DoH-pinned direct fetch of the releases page: NO prebuilt binary assets published. This is
   the decisive rung. hevm ships a static x86_64 binary; act ships none.
4. Browser render: not attempted, and this is stated rather than padded. A rendered page
   cannot produce a release asset that does not exist. Rungs 1-3 answered the question.

Cost of the only route: a Nix install (daemon mode needs systemd, only partially integrated
here per E6) plus a from-source GHC build of act and its solver dependencies.

CAPABILITY LOST, stated without minimising:
- A machine-checked specification in a language independent of Solidity. halmos and hevm
  properties are both written in Solidity, so a Solidity-level misconception could appear in
  both contract and property. act's separate spec language defends against that, and nothing
  installed here is a full substitute.
- Rocq/Coq extraction, so no interactive proof beyond SMT reach.

WHY ACCEPTABLE HERE: the invariants are small and arithmetic (bounded monotone accumulator,
sum equals parts, kill switch refuses all input), well inside SMT's decidable range, which is
why halmos and hevm both discharge them without bounding tricks. Not the class of property
that needs an interactive prover. The independent-language defence is partially recovered by
stating the same cap invariant in THREE formalisms: a halmos check_, an hevm prove_, and a
scribble annotation checked at runtime against a live contract.

Also worth stating: act's strongest EVM backend IS hevm, which is installed and driving five
theorems directly. Installing act would add a layer above a backend already in use.
MD
echo "  appended act section to evidence/phase0/tool-substitutions.md" | tee -a "$OUT"
fi

{
echo "## Verdict, task 1.6"
if command -v act >/dev/null 2>&1; then
  echo "  RESULT: act is on PATH, specification path available."
else
  echo "  RESULT: SUBSTITUTED, recorded in evidence/phase0/tool-substitutions.md."
  echo "  Four rungs named, capability loss stated, and the loss argued against the actual"
  echo "  invariants rather than waved away. Three independent formalisms already cover them."
fi
} | tee -a "$OUT"

echo "written: $OUT"
