#!/usr/bin/env bash
set -uo pipefail
while pgrep -f 69-reverify-formal >/dev/null; do sleep 30; done
grep -E "^## |RESULT|caught=|RED|GREEN|Symbolic test result|test result:|gates attempted|scripts missing" \
  /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/phase2/reverify-formal-mutation.txt | tail -60
echo "REVERIFY-DONE"
