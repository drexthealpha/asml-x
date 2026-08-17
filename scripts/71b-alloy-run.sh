#!/usr/bin/env bash
# Task 1.12 continued: run the already-built probe.
#
# The first attempt used `cargo run -q -p alloy-probe` under a 300s timeout and exited 124 with no
# output. The build itself took 17m10s for alloy 2.3.0 with the `full` feature, so 300s was not a
# generous allowance for cargo to re-check and link a binary of that size before the program even
# started. Invoke the built binary directly and give the network calls room.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/alloy.txt"
BIN="$REPO/target/debug/alloy-probe"
GUARD="0xE64b6e937Fd0d855161A5F6F0Aa1A3E01CB54c24"

{
echo
echo "## Differential run, second attempt"
echo "  binary: $BIN ($(stat -c%s "$BIN" 2>/dev/null || echo missing) bytes)"
echo "  The first attempt ran through cargo under a 300s timeout and hit it before producing"
echo "  output. Running the built binary directly removes cargo's re-check and link from the"
echo "  clock."
} | tee -a "$OUT"

if [ ! -x "$BIN" ]; then
  echo "  BINARY MISSING, build did not produce it" | tee -a "$OUT"
  exit 1
fi

GUARD_ADDRESS="$GUARD" timeout 240 "$BIN" 2>&1 | tee -a "$OUT"
RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict, task 1.12 (second attempt)"
if [ "${RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. Identical bytes from both clients for the same call at the same block,"
  echo "  and alloy confirmed chain id 1952."
  echo "  Reproduce: bash scripts/71-alloy-smoke.sh then bash scripts/71b-alloy-run.sh"
  echo
  echo "  What this buys for the 6.6 decision: alloy gives dynamic ABI encoding and an in-process"
  echo "  signer, which are exactly ADR-008's two recorded debts (no dynamic ABI, signing through"
  echo "  a cast subprocess). The differential is the evidence that migrating would not change"
  echo "  what the agent reads from the chain."
  echo
  echo "  Cost recorded honestly: alloy 2.3.0 with the full feature took 17m10s to compile on this"
  echo "  box and pulled in a TLS stack including aws-lc-rs. For a probe that makes one eth_call"
  echo "  that is a large dependency, and 6.6 should weigh it against the two debts it clears."
else
  echo "  RESULT: FAIL, exit $RC. No equivalence claimed."
fi
} | tee -a "$OUT"

echo "written: $OUT"
exit "${RC:-1}"
