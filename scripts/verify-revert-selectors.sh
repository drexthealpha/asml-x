#!/usr/bin/env bash
# Verify every revert selector in ui-v2/src/lib/revert.ts against `cast sig`.
#
# Same reasoning as verify-selectors.sh, which caught five wrong selectors out of eleven. A wrong
# selector here does not throw: the decoder simply never matches, the user gets the raw hex fallback,
# and the friendly message this file exists to produce silently never appears. That is a failure that
# looks exactly like success in every test that only checks "did an error render".
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

SRC="$REPO/ui-v2/src/lib/revert.ts"
BAD=0

check() {
  local want="$1" sig="$2"
  local got
  got=$(cast sig "$sig" 2>/dev/null)
  if [ "$got" = "$want" ]; then
    printf '  ok    %-42s %s\n' "$sig" "$want"
  else
    printf '  WRONG %-42s source %s, cast %s\n' "$sig" "$want" "$got"
    BAD=$((BAD + 1))
  fi
}

echo "== revert selectors in  =="

# Simpler and less brittle: pull each selector/signature pair straight out of the table.
python3 - "$SRC" <<'PY' > /tmp/revert_pairs.txt
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
for m in re.finditer(r'"(0x[0-9a-f]{8})":\s*\{\s*sig:\s*"([^"]+)"', s):
    print(m.group(1), m.group(2))
PY

BAD=0
while read -r SEL SIG; do
  [ -z "$SEL" ] && continue
  # A selector-only signature like "InvalidSignature" without parens is a typo worth catching.
  case "$SIG" in
    *"("*) ;;
    *) printf '  MALFORMED %-40s %s  (missing parentheses)\n' "$SIG" "$SEL"; BAD=$((BAD + 1)); continue ;;
  esac
  check "$SEL" "$SIG"
done < /tmp/revert_pairs.txt

echo
echo "wrong selectors: $BAD"
[ "$BAD" -eq 0 ] || exit 1
