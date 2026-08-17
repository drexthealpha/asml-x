#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
D=$(date -u '+%Y-%m-%d')
cat >> "$REPO/evidence/CHAIN-OF-EVIDENCE.md" <<MD
| C-710 | Three attacks against the LIVE deployed bytecode on chain 1952, run with the deployer key which is the most privileged key in the system, all failed with decoded revert selectors: a direct venue fill returned NotAuthorisedTaker(deployer) against a live order holding 5e18 remaining base while authorisedTakers[BatchExecutor] reads true, raising the fee to 9000 bps and separately to 99 bps both returned FeeNotLowered(50, x), and calling charge returned NotCharger. An appointed charger still cannot inflate the event count for free, because charge emits and then transfers and reverts on a short balance delta, so every event costs its own face value | evidence/phase7/phase7-redteam.md | bash scripts/109-phase7-redteam.sh | DEMONSTRATED | 7.8 | $D |
MD
echo "rows now: $(grep -c '^| C-' "$REPO/evidence/CHAIN-OF-EVIDENCE.md")"
