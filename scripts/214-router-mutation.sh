#!/usr/bin/env bash
# R-MUTATE for RouterExecutor: break the exact thing the tests guard, confirm RED, restore, GREEN.
#
# WHAT IS BEING PROVED. RouterExecutor forwards opaque third-party calldata, and the ONLY thing
# standing between that and a drained vault is the measured balance check. A test suite that passes
# with that check deleted would be decoration on the most dangerous contract in the system.
#
# THE MUTATION: delete the `if (amountOut < minOut) revert InsufficientOutput(...)` line. If the
# thieving-router test still passes, the check is not load-bearing and the suite is worthless.
set -uo pipefail
cd "$(dirname "$0")/../contracts"
export PATH="$HOME/.foundry/bin:$PATH"

SRC="src/RouterExecutor.sol"
cp "$SRC" "$SRC.bak"
# Restore on ANY exit, including a failed forge run. Leaving a mutated contract on disk would be a
# far worse outcome than a failed script.
trap 'mv -f "$SRC.bak" "$SRC"' EXIT

echo "=== BASELINE, unmutated ==="
forge test --match-contract RouterExecutorTest 2>&1 | tail -4

echo
echo "=== MUTANT: the output check is deleted ==="
sed -i 's|if (amountOut < minOut) revert InsufficientOutput(amountOut, minOut);|// MUTANT: check deleted|' "$SRC"
grep -q "MUTANT: check deleted" "$SRC" || { echo "ABORT: the mutation did not apply, so nothing was proved"; exit 1; }

forge test --match-contract RouterExecutorTest 2>&1 | tail -14
echo
echo "The two tests that must go RED above are:"
echo "  test_a_router_that_pays_nothing_reverts_and_keeps_the_funds"
echo "  test_under_delivery_below_min_out_reverts"
echo "If either still PASSES, the balance check guards nothing."
