#!/usr/bin/env bash
# Run the RWA guard against every tokenized equity and print the verdict, rule by rule.
#
# THIS IS THE INTEGRATION, and the earlier plan was not. Listing xStock prices on one screen and
# contract addresses on another shows that both exist and leaves the connection to the imagination.
# What makes the contracts real is watching them decide: every rule below is a parameter read from
# the deployed RwaRiskGuard, evaluated against live market data for a named instrument, producing
# the same answer the agent gets before it trades.
#
# A rule whose input cannot be read is UNKNOWN, and unknown never becomes approved. A guard that
# passes an instrument it could not check is worse than no guard.
#
# EVIDENCE PATH: evidence/phase20/rwa-verdicts.txt
set -uo pipefail
cd "$(dirname "$0")"

OUT="../evidence/phase20/rwa-verdicts.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

python3 rwa_verdicts.py
