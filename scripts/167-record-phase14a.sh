#!/usr/bin/env bash
# Record C-1400 through C-1402 (tasks 14.1, 14.2, 14.3) into the evidence chain.
#
# Appended by a script rather than by hand so the rows cannot drift from the files they cite: the
# guard below refuses to append if any cited evidence path is missing.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN="$REPO/evidence/CHAIN-OF-EVIDENCE.md"

for f in evidence/phase14/differential.md evidence/phase14/invariants.md \
         evidence/phase14/trace.md evidence/phase14/otel-stdout.txt \
         evidence/phase14/decision-trace.jsonl; do
  if [ ! -s "$REPO/$f" ]; then
    echo "MISSING OR EMPTY: $f. Refusing to append a row citing a file that is not there."
    exit 1
  fi
done

if grep -q "C-1400" "$CHAIN"; then
  echo "already recorded"
  exit 0
fi

TODAY=$(date -u '+%Y-%m-%d')

cat >> "$CHAIN" <<EOF
| C-1400 | One rule, the per-market exposure cap, enforced in three independent implementations and shown to agree on the REVERT SELECTOR AND ITS DECODED ARGUMENTS rather than on a boolean: the live deployed guard on testnet 1952, the same bytecode replayed in revm with nothing touching the network, and the Rust risk engine. All three name selector 0x3e2ed028 with the attempted notional and the cap. The under-cap call succeeding in revm is the negative control, without which a contract that reverted on everything would pass. What this rules out is a silent OVER-refusal, the failure no single layer can detect about itself, whose only symptom is an agent that under-trades for a reason nobody can locate | evidence/phase14/differential.md | bash scripts/164-differential-proof.sh | DEMONSTRATED | 14.1 | $TODAY |
| C-1401 | Eight invariants over the vault and fee contracts hold across a 128-run, depth-64 campaign, and the suite is shown able to FAIL: removing the free-balance guard in AgentVault.openTrade makes exactly one invariant go red, invariant_committedNeverExceedsBalance, with the other seven correctly still holding because that mutation does not break solvency or the ledger sums. Two reachability tests prove the campaign reaches the committing states at all, written as ordinary tests because an anti-vacuity check written as an invariant_ fails at step zero and the same check in afterInvariant makes the fuzzer shrink to one call. Foundry's counterexample cache is cleared before every run, because an earlier version of this gate caught the mutation by REPLAYING a stored failure, which proves only that a counterexample once existed on disk | evidence/phase14/invariants.md | bash scripts/166-vault-invariants.sh | DEMONSTRATED | 14.2 | $TODAY |
| C-1402 | One real decision traced end to end through the REAL OpenTelemetry Rust SDK: five spans under one 128-bit SDK-assigned trace id, four children parented to the root by OpenTelemetry's own Context, showing the chain read at 66.6 percent of the cycle, which says optimising the decision engine would be optimising the wrong thing. The SDK's own stdout exporter output is captured alongside the JSON, because the JSON alone would look identical whether the SDK were doing the work or merely linked. ADR-019 originally REJECTED OpenTelemetry on the untested claim that crates.io was unreachable from this machine; index.crates.io and static.crates.io both return 200 and cargo add resolved first try, and the ADR now records the correction | evidence/phase14/trace.md, evidence/phase14/otel-stdout.txt | bash scripts/165-decision-trace.sh | DEMONSTRATED | 14.3 | $TODAY |
EOF

echo "appended C-1400..C-1402"
grep -c "^| C-" "$CHAIN"
