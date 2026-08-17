#!/usr/bin/env bash
# Task 0.7: append one row to CHAIN-OF-EVIDENCE.md.
# Usage: bash scripts/43-chain-add.sh C-123 "claim text" "evidence/path.txt" "bash scripts/x.sh" DEMONSTRATED 4.2
#
# Refuses a row whose evidence file does not exist, because that is exactly the unbacked
# claim the index exists to prevent.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CID="${1:?claim id required, e.g. C-401}"
CLAIM="${2:?claim text required}"
EV="${3:?evidence path required}"
CMD="${4:?reproduce command required}"
LABEL="${5:?DEMONSTRATED or INFERRED}"
TASK="${6:?task number required}"

INDEX="$REPO/evidence/CHAIN-OF-EVIDENCE.md"

case "$LABEL" in
  DEMONSTRATED|INFERRED) ;;
  *) echo "label must be DEMONSTRATED or INFERRED, got: $LABEL"; exit 1 ;;
esac

EV_FIRST=$(printf '%s' "$EV" | cut -d, -f1 | tr -d ' ')
if [ "$LABEL" = "DEMONSTRATED" ] && [ ! -e "$REPO/$EV_FIRST" ]; then
  echo "REFUSED: $EV_FIRST does not exist, so this cannot be DEMONSTRATED."
  echo "Either produce the artifact first, or label it INFERRED with the basis stated."
  exit 1
fi

if grep -q "^| $CID |" "$INDEX" 2>/dev/null; then
  echo "REFUSED: $CID already present. Edit the row rather than duplicating it."
  exit 1
fi

printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
  "$CID" "$CLAIM" "$EV" "$CMD" "$LABEL" "$TASK" "$(date -u '+%Y-%m-%d')" >> "$INDEX"

echo "added $CID ($LABEL, task $TASK)"
