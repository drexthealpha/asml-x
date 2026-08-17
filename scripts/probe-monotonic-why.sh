#!/usr/bin/env bash
# Is check_feeIsMonotonicInNotional a TIMEOUT or a real COUNTEREXAMPLE?
#
# "1 failed" from halmos covers both, and they mean opposite things. A timeout means the solver ran
# out of road. A counterexample means fee monotonicity is genuinely violated, which would be a bug
# in the fee maths, and this project ships a fee on every executed trade.
#
# Nothing is filtered here. The previous probe grepped the output and threw away the reason.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO/contracts"

export PATH="$HOME/.local/bin:$HOME/.foundry/bin:$PATH"
OUT="$REPO/evidence/phase18/monotonic-why.txt"
mkdir -p "$(dirname "$OUT")"

echo "=== quoteFee source ==="
sed -n '/function quoteFee/,/^    }/p' "$REPO/contracts/src/FeeCollector.sol"
echo
echo "=== the theorem ==="
sed -n '/check_feeIsMonotonicInNotional/,/^    }/p' "$REPO/contracts/test/FeeFormal.t.sol"
echo
echo "=== halmos, 120s, full unfiltered output ==="
timeout 300 halmos --contract FeeFormalTest \
  --function check_feeIsMonotonicInNotional \
  --solver-timeout-assertion 120000 2>&1 \
  | sed -r 's/\x1B\[[0-9;]*[mK]//g' | tail -40
