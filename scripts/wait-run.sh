#!/usr/bin/env bash
# Block until the agent run finishes, then print the tail and the journal stats.
set -uo pipefail
while pgrep -x asml >/dev/null; do sleep 20; done
tail -16 /home/zulab/asml-run2.log
echo "=== journal ==="
wc -l /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/journal.jsonl
grep -c '"tx_hash": *"0x' /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/evidence/journal.jsonl || true
echo "RUN-DONE"
