#!/usr/bin/env bash
# Task 6.6: measure what the cast subprocess actually costs, so the signing decision rests on a
# number rather than on a preference.
#
# THINKING: #30 trade-off (in-process signing buys latency and costs a dependency plus a key in more
# address space), #27 opportunity-cost (days before the deadline, what else does this displace),
# #23 second-order (a signer in the runtime changes what a runtime compromise means).
#
# WHAT IS MEASURED: the wall time of the three things a submission does, separately, so the decision
# is made against the DOMINANT cost rather than the annoying one.
#
#   1. keystore decrypt          scrypt, once per `cast send`
#   2. cast process spawn        fork, exec, dynamic linking
#   3. chain round trips         estimate gas, send, and the block time before inclusion
#
# EVIDENCE PATH declared before code: evidence/phase6/signing-decision.md
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

OUT="$REPO/evidence/phase6/signing-latency.txt"
mkdir -p "$(dirname "$OUT")"
RPC="$XLAYER_TESTNET_RPC"
PASS_TEXT="$(cat "$PASSFILE")"

{
echo "Signing path latency, task 6.6"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## 1. keystore decrypt alone (scrypt), 3 runs"
} 2>&1 | tee "$OUT"

for n in 1 2 3; do
  START=$(date +%s.%N)
  timeout 60 cast wallet address --keystore "$KEYFILE" --password "$PASS_TEXT" > /dev/null 2>&1
  END=$(date +%s.%N)
  printf '  run %s: %.3fs\n' "$n" "$(echo "$END - $START" | bc)" | tee -a "$OUT"
done

{
echo
echo "## 2. cast process spawn with no crypto and no network, 3 runs"
} | tee -a "$OUT"
for n in 1 2 3; do
  START=$(date +%s.%N)
  timeout 60 cast --version > /dev/null 2>&1
  END=$(date +%s.%N)
  printf '  run %s: %.3fs\n' "$n" "$(echo "$END - $START" | bc)" | tee -a "$OUT"
done

{
echo
echo "## 3. one chain round trip, 3 runs"
} | tee -a "$OUT"
for n in 1 2 3; do
  START=$(date +%s.%N)
  timeout 60 cast block-number --rpc-url "$RPC" > /dev/null 2>&1
  END=$(date +%s.%N)
  printf '  run %s: %.3fs\n' "$n" "$(echo "$END - $START" | bc)" | tee -a "$OUT"
done

{
echo
echo "## 4. the number that matters: read-to-landing drift, measured over 39 real submissions"
echo "  From evidence/phase4/seam-test.md, every submitted decision checked against its receipt:"
grep -E "drift blocks|read to landing" "$REPO/evidence/phase4/seam-test.md" 2>/dev/null | sed 's/^/    /'
echo
echo "## Interpretation"
echo "  Compare the parts against the whole. If keystore decrypt plus process spawn is a small"
echo "  fraction of the 22 to 30 block read-to-landing drift, then replacing the subprocess with an"
echo "  in-process signer removes a small part of the latency and leaves the dominant part, which is"
echo "  the chain, untouched."
} | tee -a "$OUT"

echo "written: $OUT"
