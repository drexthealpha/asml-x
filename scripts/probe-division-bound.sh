#!/usr/bin/env bash
# At what bound does division monotonicity actually close?
#
# 2**112 times out. Rather than guess again, this walks the bound down and reports the largest one
# that PROVES, so the theorem states a range the solver genuinely discharged instead of a range that
# sounds good and times out.
#
# Written as a script because E4 strips $vars through `wsl -- bash -c`, which already cost one run
# here: the loop variable vanished and both iterations ran the default theorem set.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO/contracts"
export PATH="$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

SRC="test/FeeFormal.t.sol"
cp "$SRC" "$SRC.probe.bak"

for BOUND in 64 48 32; do
  python3 - "$SRC" "$BOUND" <<'PY'
import re, sys
p, b = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
s = re.sub(r"(check_feeDivisionPreservesOrder.*?if \(x >= 2 \*\* )\d+( \|\| y >= 2 \*\* )\d+",
           lambda m: m.group(1) + b + m.group(2) + b, s, flags=re.S)
open(p, "w", encoding="utf-8", newline="\n").write(s)
PY
  echo "--- bound 2**$BOUND ---"
  timeout 200 halmos --contract FeeFormalTest \
    --function check_feeDivisionPreservesOrder \
    --solver-timeout-assertion 150000 2>&1 \
    | sed -r 's/\x1B\[[0-9;]*[mK]//g' \
    | grep -E "^\[(PASS|FAIL|TIMEOUT)\]" || echo "  (no verdict line)"
done

mv "$SRC.probe.bak" "$SRC"
echo
echo "source restored"
