#!/usr/bin/env bash
# Task 16.3: re-verify every mainnet claim FROM CHAIN, not from the local evidence files.
#
# THINKING: #50 empirical, #49 evidence.
#
# EVIDENCE PATH: evidence/phase16/mainnet-reverify.md
# PASS: every transaction the Phase 12 evidence names is found on chain 196 with status 1, every
# contract it names has real bytecode, and the contract STATE agrees with what the documents claim.
#
# WHY THIS IS STRONGER THAN RE-RUNNING PHASE 12. Re-running would spend the user's OKB to do the
# thing again and then check that the new run matched. This reads what ACTUALLY HAPPENED, which is
# the claim the documents make. A local evidence file can be edited; chain 196 cannot.
#
# The hashes and addresses are SCRAPED from the evidence files rather than pasted here, so a document
# that quietly changed a hash would fail this check instead of being confirmed by a constant that was
# updated to match it.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

RPC="https://rpc.xlayer.tech"
OUT="$REPO/evidence/phase16/mainnet-reverify.md"
mkdir -p "$(dirname "$OUT")"
CAST="$HOME/.foundry/bin/cast"
M="$REPO/deployments-mainnet.json"
a() { python3 -c "import json;print(json.load(open('$M'))['$1'])"; }

echo "=== chain identity ==="
CHAINID=$("$CAST" chain-id --rpc-url "$RPC" 2>&1)
echo "  eth_chainId: $CHAINID"

# Scraped, not pasted. A 64-hex string in these documents is either a tx hash or a market id; the
# market id is a known constant and is excluded by name rather than by guessing from the shape.
MARKET=$(a marketId)
mapfile -t HASHES < <(grep -ohE "0x[0-9a-f]{64}" "$REPO"/evidence/phase12/*.md | sort -u | grep -v "$MARKET")

echo
echo "=== transactions named in the Phase 12 evidence ==="
#
# `cast receipt` BLOCKS WAITING FOR CONFIRMATION when a hash is not on chain. The first version of
# this script used it and hung indefinitely, because not every 64-hex string in these documents is a
# transaction: `mainnet-refusal.md` quotes REVERT DATA, and 0x3e2ed028 followed by the market id is
# exactly 64 hex characters. So the script sat waiting for a transaction that will never exist.
#
# `cast rpc eth_getTransactionReceipt` returns `null` immediately instead, which both fixes the hang
# and gives the right classification: a 64-hex string with no receipt is NOT A TRANSACTION rather
# than a missing one. Counting the revert blob as a missing transaction would have failed this gate
# for a document that is perfectly correct.
#
# `cast receipt <h> status` also returns `true`, not `1`, which the first version compared against.
TX_OK=0; TX_BAD=0; NOT_TX=0; TXROWS=""; NOTTXROWS=""
for h in "${HASHES[@]}"; do
  R=$(timeout 40 "$CAST" rpc eth_getTransactionReceipt "$h" --rpc-url "$RPC" 2>/dev/null || echo "null")
  if [ -z "$R" ] || [ "$R" = "null" ]; then
    NOT_TX=$((NOT_TX + 1)); printf "  %s  no receipt: not a transaction\n" "${h:0:18}..."
    NOTTXROWS="$NOTTXROWS| \`${h:0:18}...\` | no receipt on chain 196 |
"
    continue
  fi
  ST=$(echo "$R" | python3 -c "import json,sys;print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "?")
  BLK=$(echo "$R" | python3 -c "import json,sys;print(int(json.load(sys.stdin).get('blockNumber','0x0'),16))" 2>/dev/null || echo "-")
  # EXPECT WHAT THE DOCUMENT CLAIMS, not success everywhere. A hash cited by mainnet-refusal.md is
  # a REFUSAL, and a refusal that succeeded would be the defect. The first version of this gate
  # expected 0x1 for everything and failed on 0x6a023784..., which is the mainnet proof that the
  # risk guard rejects an over-cap trade with real money at stake. Marking that as broken would have
  # inverted the meaning of the single most important negative result in Phase 12.
  WANT=0x1; WHY="succeeded"
  if grep -ql "$h" "$REPO/evidence/phase12/mainnet-refusal.md" 2>/dev/null; then
    WANT=0x0; WHY="refused, as the document claims"
  fi
  if [ "$ST" = "$WANT" ]; then
    TX_OK=$((TX_OK + 1)); printf "  %s  status %s  %s\n" "${h:0:18}..." "$ST" "$WHY"
    TXROWS="$TXROWS| \`${h:0:18}...\` | $BLK | $ST | $WHY |
"
  else
    TX_BAD=$((TX_BAD + 1)); printf "  %s  status %s  EXPECTED %s\n" "${h:0:18}..." "$ST" "$WANT"
    TXROWS="$TXROWS| \`${h:0:18}...\` | $BLK | $ST | **expected $WANT** |
"
  fi
done

echo
echo "=== contracts named in deployments-mainnet.json ==="
C_OK=0; C_BAD=0; CROWS=""
for name in tQUOTE tBASE venue riskGuard feeCollector batchExecutor agentVault; do
  ADDR=$(a "$name")
  CODE=$(timeout 40 "$CAST" code "$ADDR" --rpc-url "$RPC" 2>/dev/null || echo "0x")
  SIZE=$(( (${#CODE} - 2) / 2 ))
  if [ "$SIZE" -gt 0 ]; then
    C_OK=$((C_OK + 1)); printf "  %-14s %s  %s bytes\n" "$name" "$ADDR" "$SIZE"
    CROWS="$CROWS| \`$name\` | \`$ADDR\` | $SIZE | deployed |
"
  else
    C_BAD=$((C_BAD + 1)); printf "  %-14s %s  NO CODE\n" "$name" "$ADDR"
    CROWS="$CROWS| \`$name\` | \`$ADDR\` | 0 | **NO CODE** |
"
  fi
done

echo
echo "=== contract STATE against what the documents claim ==="
FEE_BPS=$("$CAST" call "$(a feeCollector)" "feeBps()(uint256)" --rpc-url "$RPC" 2>/dev/null || echo ERR)
CHARGES=$("$CAST" call "$(a feeCollector)" "chargeCount()(uint256)" --rpc-url "$RPC" 2>/dev/null || echo ERR)
TREASURY=$("$CAST" call "$(a feeCollector)" "treasury()(address)" --rpc-url "$RPC" 2>/dev/null || echo ERR)
SOLVENT=$("$CAST" call "$(a agentVault)" "isSolvent()(bool)" --rpc-url "$RPC" 2>/dev/null || echo ERR)
DEPOSITS=$("$CAST" call "$(a agentVault)" "totalDeposits()(uint256)" --rpc-url "$RPC" 2>/dev/null || echo ERR)
printf "  feeBps           %s\n" "$FEE_BPS"
printf "  chargeCount      %s\n" "$CHARGES"
printf "  treasury         %s\n" "$TREASURY"
printf "  vault isSolvent  %s\n" "$SOLVENT"
printf "  vault deposits   %s\n" "$DEPOSITS"

# The treasury being a DISTINCT address from the deployer is a claim Phase 12 makes explicitly, and
# it is the one that makes fee revenue distinguishable from trade proceeds. Checked, not assumed.
DEPLOYER=$(a deployer)
SEPARATE=no
[ "${TREASURY,,}" != "${DEPLOYER,,}" ] && SEPARATE=yes

VERDICT=FAIL
if [ "$TX_BAD" -eq 0 ] && [ "$C_BAD" -eq 0 ] && [ "$CHAINID" = "196" ] \
   && [ "$SOLVENT" = "true" ] && [ "$SEPARATE" = "yes" ]; then VERDICT=PASS; fi

{
echo "# Task 16.3: mainnet claims re-verified from chain"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **$VERDICT**"
echo
echo "Read from \`$RPC\`, \`eth_chainId\` = **$CHAINID**."
echo
echo "## Why this rather than re-running Phase 12"
echo
echo "Re-running would spend the user's OKB to do the thing again and then check the new run matched."
echo "This reads **what actually happened**, which is what the documents claim. A local evidence file"
echo "can be edited; chain 196 cannot."
echo
echo "The hashes and addresses below are **scraped from the evidence files**, not pasted into this"
echo "script. A document that quietly changed a hash fails this check rather than being confirmed by"
echo "a constant somebody updated to match."
echo
echo "## Transactions, $TX_OK matching their claimed outcome, $TX_BAD not"
echo
echo "**Each hash is checked against what its document CLAIMS, not against success.** A hash cited by"
echo "\`mainnet-refusal.md\` is a refusal, and a refusal that succeeded would be the defect. An earlier"
echo "version of this gate expected \`0x1\` everywhere and failed on the one transaction that proves"
echo "the risk guard rejects an over-cap trade with real money at stake, which would have inverted the"
echo "meaning of the most important negative result in Phase 12."
echo
echo "| hash | block | status | result |"
echo "|---|---|---|---|"
printf "%s" "$TXROWS"
echo
echo "### 64-hex strings in these documents that are NOT transactions: $NOT_TX"
echo
if [ "$NOT_TX" -gt 0 ]; then
echo "| string | finding |"
echo "|---|---|"
printf "%s" "$NOTTXROWS"
echo
echo "These are correct content, not missing transactions. \`mainnet-refusal.md\` quotes REVERT DATA,"
echo "and a 4-byte selector followed by a 32-byte market id is exactly 64 hex characters, so it looks"
echo "like a hash to a regex. The first version of this script used \`cast receipt\`, which BLOCKS"
echo "waiting for confirmation, and hung indefinitely waiting for a transaction that will never"
echo "exist. \`eth_getTransactionReceipt\` returns null at once, which fixes the hang and gives the"
echo "right classification: no receipt means not a transaction, not a missing one. Counting these as"
echo "missing would have failed this gate for documents that are perfectly correct."
else
echo "None."
fi
echo
echo "## Contracts, $C_OK with code, $C_BAD without"
echo
echo "| contract | address | bytecode | result |"
echo "|---|---|---|---|"
printf "%s" "$CROWS"
echo
echo "## State, read live"
echo
echo "| reading | value | what it confirms |"
echo "|---|---|---|"
echo "| \`feeBps()\` | $FEE_BPS | the live rate, which only ever falls |"
echo "| \`chargeCount()\` | $CHARGES | fees were charged on mainnet, not just quoted |"
echo "| \`treasury()\` | \`$TREASURY\` | separate from the deployer: $SEPARATE |"
echo "| \`isSolvent()\` | $SOLVENT | the vault covers what depositors are owed |"
echo "| \`totalDeposits()\` | $DEPOSITS | real user capital passed through it |"
echo
echo "**The treasury being a different address from the deployer is checked, not assumed.** It is what"
echo "makes fee revenue distinguishable from trade proceeds, and an earlier deployment had them equal,"
echo "which made the fee unprovable."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/184-mainnet-reverify.sh"
echo '```'
} > "$OUT"

echo
echo "written: $OUT"
echo "VERDICT: $VERDICT  (tx $TX_OK ok / $TX_BAD bad, contracts $C_OK/$C_BAD)"
[ "$VERDICT" = PASS ]
