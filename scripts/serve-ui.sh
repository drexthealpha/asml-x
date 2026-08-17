#!/usr/bin/env bash
# Serve both UI builds so the Windows-side browser can actually reach them.
#
# WHY --bind 0.0.0.0 AND NOT 127.0.0.1: a server bound to WSL's loopback is reachable from inside the
# distro and NOT from the Windows host, because WSL2 runs its own network namespace. Every
# measurement attempt that "hung" or returned chrome-error was this: curl inside WSL got 200 while the
# browser got nothing. Binding to 0.0.0.0 lets the host's localhost forwarding through.
#
#   4173  the product build, ui-v2/dist
#   4176  the 600-row synthetic load fixture for task 5.3, /home/zulab/loadtest-check
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
PY=/home/zulab/.asml-venv/bin/python

pkill -f "http.server 4173" 2>/dev/null || true
pkill -f "http.server 4176" 2>/dev/null || true
sleep 1

cd "$REPO/ui-v2/dist" && nohup "$PY" -m http.server 4173 --bind 0.0.0.0 > /home/zulab/serve-4173.log 2>&1 &
cd /home/zulab/loadtest-check && nohup "$PY" -m http.server 4176 --bind 0.0.0.0 > /home/zulab/serve-4176.log 2>&1 &
sleep 2

for P in 4173 4176; do
  printf '  %s -> %s\n' "$P" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$P/index.html")"
done
ss -ltn | grep -E '4173|4176'
