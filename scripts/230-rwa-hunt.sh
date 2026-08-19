#!/usr/bin/env bash
# Hunt for tokenized real-world assets on X Layer, across EVERY surface the aggregator exposes.
#
# WHY THIS RUNS AT ALL. I stated twice that X Layer carries no tokenized gold, silver or equity
# index, based on the aggregator's `all-tokens` list for chain 196. That list is one surface. The
# aggregator also has a SEARCH endpoint, and the market API has its own token universe, and neither
# was checked. "I looked in one place and did not find it" is not "it does not exist", and I
# reported the second when I had only established the first.
#
# This script checks every surface by name, so the answer is exhaustive rather than convenient.
#
# EVIDENCE PATH: evidence/phase20/rwa-hunt.txt
set -uo pipefail
cd "$(dirname "$0")"

OUT="../evidence/phase20/rwa-hunt.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

echo "=== 1. the aggregator's full token list for chain 196 ==="
python3 rwa_hunt.py list

echo
echo "=== 2. token SEARCH, the surface never checked ==="
for q in gold XAU PAXG XAUT silver XAG oil treasury bond stock equity nasdaq SPX tesla apple RWA real estate; do
  python3 rwa_hunt.py search "$q"
done

echo
echo "=== 3. hot tokens on this chain, in case an RWA is trending but unlisted ==="
python3 rwa_hunt.py hot
