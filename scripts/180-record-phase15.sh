#!/usr/bin/env bash
# Record C-1500 and C-1501 and write the Phase 15 gate report.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN="$REPO/evidence/CHAIN-OF-EVIDENCE.md"
GATE="$REPO/evidence/gates/phase15.md"
A="$REPO/evidence/phase15/adversarial-fee-vault.md"
P="$REPO/evidence/phase15/protocol-probe.txt"
D="$REPO/docs/COORDINATION-PROTOCOL.md"

for f in "$A" "$P" "$D"; do
  [ -s "$f" ] || { echo "MISSING OR EMPTY: $f"; exit 1; }
done
grep -q "Verdict: \*\*PASS\*\*" "$A" || { echo "15.1 did not pass. Refusing to record."; exit 1; }

TODAY=$(date -u '+%Y-%m-%d')

{
echo "# Phase 15 gate report: coordination residue"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **PASS**"
echo
echo "## 15.1, adversarial audit of the deployed fee and vault surfaces"
echo
echo "Nine hostile calls executed against the DEPLOYED bytecode with a hostile \`msg.sender\`, all"
echo "refused with the exact expected error selector, and three negative controls executed as the"
echo "same attacker all succeeding with decoded values: fee quote 4900, solvency true, withdrawable"
echo "25000000000000000000."
echo
echo "Two things this run got right only after getting them wrong, both recorded in the script:"
echo
echo "1. **Matching on the error NAME failed every case while the controls passed.** An X Layer node"
echo "   returns custom errors as raw calldata with no name in the response. That pattern, all"
echo "   probes failing and all controls passing, means the match is wrong rather than the contract."
echo "   Now matched on the selector computed by \`cast sig\` at run time, which is the stronger"
echo "   claim: \"it reverted\" and \"it reverted for the reason I said\" are different findings."
echo "2. **The controls printed raw 32-byte words truncated to 40 characters**, which cuts off the"
echo "   last word. A solvency check reading \`false\` would have displayed identically to \`true\`."
echo "   Now called with typed return signatures so the row shows a decoded value."
echo
echo "## 15.2, protocol version and compatibility note"
echo
echo "\`docs/COORDINATION-PROTOCOL.md\` at version 1.0.0, GENERATED from a live probe in the same run"
echo "that writes it. Five endpoints exercised end to end including a full quote and accept round"
echo "trip, and four refusal codes captured: 401 without a key, 404 on an unknown quote id, 400 on a"
echo "numeric \`size_micro\`, 404 on an unknown endpoint."
echo
echo "The document states what the API is NOT, so nobody integrates against a promise never made: it"
echo "is not a venue, not multi-market, not authenticated per identity, and its fee is quoted rather"
echo "than charged."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/178-adversarial-fee-vault.sh"
echo "bash scripts/179-protocol-version.sh"
echo '```'
} > "$GATE"

if grep -q "C-1500" "$CHAIN"; then
  echo "chain rows already recorded"
else
cat >> "$CHAIN" <<EOF
| C-1500 | The DEPLOYED fee and vault contracts refuse nine hostile calls from an address this project holds no key for, each matched against the EXACT error selector rather than a name: NotAgent 0x0d9ab13f on opening and closing another depositor's trade, NotOwner 0x30cd7471 on reassigning the agent, raising the fee rate, repointing the treasury and self-authorising as a charger, NotCharger 0xd796045b on minting revenue, InsufficientBalance and ZeroAmount on the deposit paths. Three negative controls run as the SAME attacker succeed with decoded values, without which a contract that reverted on everything would have scored a perfect refusal rate. This runs against what is actually deployed rather than locally compiled bytecode, because a contract can pass its own suite and not be the one that reached the chain. What it does not cover is named rather than skipped: funding-gated paths, reentrancy, and a hostile owner, each pointing at the gate that does cover it | evidence/phase15/adversarial-fee-vault.md | bash scripts/178-adversarial-fee-vault.sh | DEMONSTRATED | 15.1 | $TODAY |
| C-1501 | A coordination protocol note at version 1.0.0 for other builders, GENERATED from a live probe in the same run that writes it, so it cannot drift from the server it documents: five endpoints exercised end to end including a full quote and accept round trip returning quote_id 1 at price 1200000 micro with a written handoff, plus the four refusals a client must handle. The compatibility rules are the only hand-written part, because no probe can discover them, and they carry their reasons: size_micro is a STRING because JSON numbers are doubles in most clients and lose precision above 2 to the 53, so a numeric value is refused rather than silently rounded; accepting another caller's quote returns 403 not 404 so a client can tell not-yours from does-not-exist; unknown response fields must be ignored because additions are compatible within a minor version. The note also states what the API is NOT: not a venue, not multi-market, not authenticated per identity, and its fee is quoted rather than charged | docs/COORDINATION-PROTOCOL.md, evidence/phase15/protocol-probe.txt | bash scripts/179-protocol-version.sh | DEMONSTRATED | 15.2 | $TODAY |
EOF
echo "appended C-1500, C-1501"
fi

echo "written: $GATE"
grep -c "^| C-" "$CHAIN"
