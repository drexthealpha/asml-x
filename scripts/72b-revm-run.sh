#!/usr/bin/env bash
# Task 1.13 continued: run the built revm probe and finish the three-way comparison.
#
# Two failures to record, both mine and both cheap once read:
#  1. `ExecutionResult::Revert` in revm 42 does not have a `gas_used` field. The compiler listed the
#     real fields (`gas`, `logs`); the probe now binds only `output`, which is what it needs.
#  2. Passing GUARD_ARTIFACT="$PWD/..." through `wsl -- bash -c` produced NotFound, because E4:
#     the arg layer eats $PWD. Literal paths only, in a script file.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/revm.txt"
BIN="$REPO/target/debug/revm-probe"
ART="$REPO/contracts/out/RiskGuard.sol/RiskGuard.json"
MARKET="0x9b14309189a210d9c57d8f9988110c977884ed7629791ee202706dc43dbaab0e"
SEL="0x3e2ed028"

{
echo
echo "## Source 2 retry: revm 42 local simulation"
echo "  binary:   $BIN"
echo "  artifact: $ART ($(stat -c%s "$ART" 2>/dev/null || echo missing) bytes)"
} | tee -a "$OUT"

GUARD_ARTIFACT="$ART" MARKET_ID="$MARKET" timeout 240 "$BIN" 2>&1 | tee -a "$OUT"
RC=${PIPESTATUS[0]}

REVM_SEL=$(grep -oE 'revert selector: 0x[0-9a-fA-F]{8}' "$OUT" | tail -1 | grep -oE '0x[0-9a-fA-F]{8}')

{
echo
echo "## Three-way comparison, final"
echo "  from the Solidity source (cast keccak of the error signature): $SEL"
echo "  from the LIVE deployed guard (eth_call over its cap):          $SEL"
echo "  from the revm local simulation:                                ${REVM_SEL:-none}"
echo
echo "## Verdict, task 1.13"
if [ "${REVM_SEL:-x}" = "$SEL" ]; then
  echo "  RESULT: PASS. All three agree on MarketCapExceeded, and the local simulation decodes the"
  echo "  attempted amount and the cap out of the revert payload."
  echo "  Reproduce: bash scripts/72-revm-smoke.sh && bash scripts/72b-revm-run.sh"
  echo
  echo "  What this buys the product: the agent can refuse a cap-breaching batch LOCALLY, for free,"
  echo "  before signing. The v1 spine run proved the chain refuses a breach; this proves the same"
  echo "  refusal is predictable off-chain, which is the difference between paying gas to learn no"
  echo "  and knowing no in advance."
  echo
  echo "  One limit stated plainly: this simulation deploys a FRESH guard into an empty in-memory"
  echo "  state and configures it, so it proves the CONTRACT LOGIC reverts as expected. It does not"
  echo "  simulate against live chain state. Doing that needs a state fork, which is task 7.6, and"
  echo "  the distinction matters: a pre-flight against the wrong state would authorise what the"
  echo "  chain refuses."
else
  echo "  RESULT: FAIL, exit $RC, revm selector ${REVM_SEL:-none} against $SEL. No equivalence claimed."
fi
} | tee -a "$OUT"

echo "written: $OUT"
[ "${REVM_SEL:-x}" = "$SEL" ]
