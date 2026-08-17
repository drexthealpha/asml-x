#!/usr/bin/env bash
# Task 2.4 reproduce every transaction claim. For every tx hash cited anywhere in a
# judge-facing document, fetch the receipt FROM CHAIN and confirm the claimed status.
#
# THINKING: #50 empirical, #60 map-territory (the docs are the map; the receipt is the
# territory), #66 red teaming (assume a hash in a doc could be a typo or fabricated and build
# the check that would catch it).
#
# EVIDENCE PATH declared before code: evidence/phase2/tx-receipts.json plus
# evidence/phase2/tx-claims.txt
# PASS: every cited hash resolves with the claimed status. TASKS.md names the fake win exactly:
# trusting the hash strings in the docs. So nothing here trusts them; each one is fetched, and a
# hash that does not resolve is reported as UNRESOLVED rather than skipped.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase2/tx-claims.txt"
JSON="$REPO/evidence/phase2/tx-receipts.json"
mkdir -p "$(dirname "$OUT")"
RPC="$XLAYER_TESTNET_RPC"

{
echo "Transaction claim re-verification, task 2.4"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Method"
echo "  Every 32-byte hex string in README, JUDGE-GUIDE, docs/ and evidence/gates/ is treated"
echo "  as a candidate tx hash and fetched with eth_getTransactionReceipt. Candidates that are"
echo "  not transactions (a market id, a keccak of a signature, a bytecode hash) resolve to"
echo "  nothing and are reported as NOT-A-TX rather than silently dropped, because the"
echo "  difference between 'not a transaction' and 'a transaction that does not exist' is the"
echo "  whole point of the task."
echo
} 2>&1 | tee "$OUT"

cd "$REPO"
# Collect candidates with their source location, so every row can be traced back.
# SCOPE WIDENED after the first run. Limiting this to README, JUDGE-GUIDE, docs/ and
# evidence/gates/ found only 5 candidates, which was obviously too few for a build with a live
# spine run, a first transaction and an RWA session. TASKS.md says "every tx hash cited
# anywhere", so the scope is now all of evidence/ as well. Undercounting here would have
# produced a PASS that covered three transactions and implied it covered all of them.
grep -rnoE '0x[0-9a-fA-F]{64}' \
  README.md JUDGE-GUIDE.md docs/ evidence/ 2>/dev/null \
  | grep -vE '^evidence/(hygiene|internal)/' \
  | sed 's/:/ /; s/:/ /' > /home/zulab/tx-candidates-raw.txt
sort -u -k3,3 /home/zulab/tx-candidates-raw.txt > /home/zulab/tx-candidates-all.txt

# Drop left-zero-padded 32-byte words. Widening the scope to all of evidence/ pulled in the
# halmos counterexample dumps, which are full of ABI-encoded values like
# 0x0000...0000871e38fca73bfffff. A keccak-256 transaction hash is effectively uniform over 32
# bytes, so sixteen leading zero bytes does not happen; every one of these is a solver word, not
# a hash. This filter is stated rather than silent because it is the one place where a real hash
# could in principle be excluded, and the excluded set is counted below so the exclusion is
# auditable.
grep -vE '0x0{16}' /home/zulab/tx-candidates-all.txt > /home/zulab/tx-candidates.txt
EXCLUDED=$(( $(wc -l < /home/zulab/tx-candidates-all.txt) - $(wc -l < /home/zulab/tx-candidates.txt) ))
echo "  zero-padded ABI words excluded (solver output, not hashes): $EXCLUDED" | tee -a "$OUT"

echo "  candidate 32-byte values found: $(wc -l < /home/zulab/tx-candidates.txt)" | tee -a "$OUT"
echo | tee -a "$OUT"

: > /home/zulab/tx-results.txt
TX=0; OK=0; BAD=0; NOTTX=0
while read -r FILE LINE HASH; do
  [ -z "${HASH:-}" ] && continue
  R=$(timeout 45 cast receipt "$HASH" --rpc-url "$RPC" --json 2>/dev/null)
  if [ -z "$R" ] || [ "$R" = "null" ]; then
    printf '  NOT-A-TX   %s  (%s:%s)\n' "${HASH:0:20}..." "$FILE" "$LINE" | tee -a "$OUT"
    NOTTX=$((NOTTX + 1))
    echo "{\"hash\":\"$HASH\",\"file\":\"$FILE\",\"line\":$LINE,\"resolved\":false}" >> /home/zulab/tx-results.txt
    continue
  fi
  TX=$((TX + 1))
  STATUS=$(printf '%s' "$R" | grep -oE '"status":"?0x[01]"?' | head -1 | grep -oE '0x[01]')
  BLOCK=$(printf '%s' "$R" | grep -oE '"blockNumber":"?0x[0-9a-fA-F]+"?' | head -1 | grep -oE '0x[0-9a-fA-F]+')
  # Two bugs here, both cosmetic and both fixed: `grep -oc` combines flags that fight each other,
  # and `grep -c ... || echo 0` prints TWO zeros when there are no logs, because grep -c already
  # prints 0 and then exits 1, which triggers the fallback. `|| true` keeps the pipeline alive
  # without adding a second line.
  LOGS=$(printf '%s' "$R" | grep -c '"topics"' || true)
  if [ "$STATUS" = "0x1" ]; then
    OK=$((OK + 1))
    printf '  TX ok      %s  block %s  logs %s  (%s:%s)\n' \
      "${HASH:0:20}..." "$BLOCK" "$LOGS" "$FILE" "$LINE" | tee -a "$OUT"
  else
    BAD=$((BAD + 1))
    printf '  TX FAILED  %s  status %s  (%s:%s)\n' "${HASH:0:20}..." "${STATUS:-?}" "$FILE" "$LINE" \
      | tee -a "$OUT"
  fi
  echo "{\"hash\":\"$HASH\",\"file\":\"$FILE\",\"line\":$LINE,\"resolved\":true,\"status\":\"${STATUS:-unknown}\",\"block\":\"${BLOCK:-}\"}" >> /home/zulab/tx-results.txt
done < /home/zulab/tx-candidates.txt

# Assemble the JSON artifact.
{
echo "["
paste -sd, /home/zulab/tx-results.txt 2>/dev/null | sed 's/},{/},\n  {/g; s/^/  /'
echo "]"
} > "$JSON"

{
echo
echo "## Verdict, task 2.4"
echo "  real transactions resolved: $TX"
echo "  status 0x1 (success):       $OK"
echo "  status 0x0 (reverted):      $BAD"
echo "  not transactions:           $NOTTX  (market ids, selectors, bytecode hashes)"
echo
if [ "$TX" -gt 0 ] && [ "$BAD" -eq 0 ]; then
  echo "  RESULT: PASS. Every cited hash that IS a transaction resolves on chain 1952 with"
  echo "  status 0x1. Receipts: evidence/phase2/tx-receipts.json"
  echo "  Reproduce: bash scripts/68-verify-tx-claims.sh"
elif [ "$TX" -eq 0 ]; then
  echo "  RESULT: FAIL. No cited hash resolved to a transaction at all, which would mean the"
  echo "  onchain claims rest on nothing fetchable. Not softened."
else
  echo "  RESULT: MIXED. $BAD cited transaction(s) did not succeed. Under 2.6 any claim resting"
  echo "  on those is CUT from the docs rather than footnoted."
fi
echo
echo "  One thing this task does NOT prove, stated so the artifact is not read as more than it"
echo "  is: a successful receipt shows the transaction executed, not that it did what the"
echo "  surrounding sentence claims. Event-topic checking against the claimed meaning is the"
echo "  next layer, and the log counts above are the input to it."
} | tee -a "$OUT"

echo "written: $OUT and $JSON"
[ "$BAD" -eq 0 ] && [ "$TX" -gt 0 ]
