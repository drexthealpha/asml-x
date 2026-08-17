#!/usr/bin/env bash
# Block until the reproducibility audit finishes, then print its progress log.
# A script file because `for i in $(seq ...)` does not survive the wsl arg layer (E4).
set -uo pipefail
while pgrep -f 82-repro-audit >/dev/null; do sleep 30; done
tail -24 /home/zulab/repro.log
echo "AUDIT-DONE"
