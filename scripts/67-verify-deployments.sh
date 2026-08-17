#!/usr/bin/env bash
# Task 2.3 reproduce the chain and deployment claims. Re-verify chain id, block time, every
# deployed address's bytecode hash, and the deployer balance, against the LIVE chain.
#
# THINKING: #50 empirical (a deployment claim is only true if the address still returns code
# today), #6 abductive (a changed bytecode hash means a redeploy happened, and that would
# invalidate every proof and gate report pinned to the old address), #60 map-territory.
#
# EVIDENCE PATH declared before code: evidence/phase2/chain-id.txt,
# evidence/phase2/deployment-bytecode.txt
# PASS: every address returns non-empty code AND chain id is 1952. The fake win is trusting
# docs/verified/deployments.md, which is the document under test, so every address is read
# from it and then CHECKED against the chain.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN_OUT="$REPO/evidence/phase2/chain-id.txt"
CODE_OUT="$REPO/evidence/phase2/deployment-bytecode.txt"
mkdir -p "$(dirname "$CHAIN_OUT")"

RPC="$XLAYER_TESTNET_RPC"

{
echo "Chain identity re-verification, task 2.3"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Endpoint"
echo "  primary:  $RPC"
echo "  fallback: $XLAYER_TESTNET_RPC_FALLBACK"
echo
echo "## Chain id"
} 2>&1 | tee "$CHAIN_OUT"

CID=$(timeout 40 cast chain-id --rpc-url "$RPC" 2>&1 | tail -1)
{
echo "  cast chain-id -> $CID"
if [ "$CID" = "1952" ]; then
  echo "  MATCHES the claimed chain id 1952."
else
  echo "  MISMATCH. Every claim in this repo is scoped to 1952."
fi
echo
echo "  The trap, restated because it is the single easiest way to be confidently wrong here:"
echo "  chain 195 is the DEPRECATED X Layer testnet and it STILL ANSWERS. A script pointed at"
echo "  the old endpoint returns a plausible chain id, plausible blocks and no code at any of"
echo "  our addresses. That is why the address checks below are the real test, not this one."
echo
echo "## Block cadence, measured rather than quoted"
} | tee -a "$CHAIN_OUT"

B1=$(timeout 40 cast block-number --rpc-url "$RPC" 2>&1 | tail -1)
T1=$(timeout 40 cast block "$B1" --rpc-url "$RPC" --field timestamp 2>&1 | tail -1)
B0=$((B1 - 300))
T0=$(timeout 40 cast block "$B0" --rpc-url "$RPC" --field timestamp 2>&1 | tail -1)
{
echo "  head block:        $B1 at unix $T1"
echo "  300 blocks back:   $B0 at unix $T0"
if [ -n "${T1:-}" ] && [ -n "${T0:-}" ] && [ "$T1" -gt "$T0" ] 2>/dev/null; then
  SPAN=$((T1 - T0))
  echo "  span:              ${SPAN}s over 300 blocks"
  echo "  mean block time:   $(awk "BEGIN{printf \"%.3f\", $SPAN/300}")s"
  echo "  Claimed ~1.0s. Measured above. Reported as measured, not as claimed."
else
  echo "  could not measure a span, so no block-time number is claimed"
fi
echo
echo "## Deployer"
echo "  address: $DEPLOYER_ADDRESS"
echo "  balance: $(timeout 40 cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1 | tail -1) wei"
echo "  nonce:   $(timeout 40 cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$RPC" 2>&1 | tail -1)"
} | tee -a "$CHAIN_OUT"

# ---------------------------------------------------------------------------
# Bytecode. Addresses are EXTRACTED from the document under test, so a typo or an
# invented address in that document fails here rather than being read past.
# ---------------------------------------------------------------------------
{
echo "Deployment bytecode re-verification, task 2.3"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Method"
echo "  Addresses are parsed out of docs/verified/deployments.md, the document under test."
echo "  Nothing is typed in here from memory. Each one gets eth_getCode and a keccak of the"
echo "  returned bytecode, so a redeploy shows up as a changed hash even when the address is"
echo "  unchanged."
echo
} 2>&1 | tee "$CODE_OUT"

grep -oE '`0x[0-9a-fA-F]{40}`' "$REPO/docs/verified/deployments.md" \
  | tr -d '`' | sort -u > /home/zulab/deployed-addrs.txt

FAIL=0
COUNT=0
while read -r A; do
  [ -z "$A" ] && continue
  COUNT=$((COUNT + 1))
  CODE=$(timeout 60 cast code "$A" --rpc-url "$RPC" 2>&1 | tail -1)
  LEN=${#CODE}
  LABEL=$(grep -m1 "$A" "$REPO/docs/verified/deployments.md" | sed 's/|/ /g' | awk '{print $1, $2}')
  if [ "$CODE" = "0x" ] || [ -z "$CODE" ]; then
    printf '  %s  EMPTY CODE  %s\n' "$A" "$LABEL" | tee -a "$CODE_OUT"
    FAIL=$((FAIL + 1))
  else
    HASH=$(printf '%s' "$CODE" | cast keccak 2>/dev/null | tail -1)
    printf '  %s  code %6d hex chars  keccak %s  %s\n' "$A" "$LEN" "${HASH:0:18}" "$LABEL" \
      | tee -a "$CODE_OUT"
  fi
done < /home/zulab/deployed-addrs.txt

{
echo
echo "## Verdict, task 2.3"
echo "  addresses checked: $COUNT"
echo "  empty code:        $FAIL"
if [ "$CID" = "1952" ] && [ "$FAIL" -eq 0 ] && [ "$COUNT" -gt 0 ]; then
  echo "  RESULT: PASS. Chain id is 1952 and every address in docs/verified/deployments.md"
  echo "  returns non-empty bytecode on the live chain."
  echo "  Reproduce: bash scripts/67-verify-deployments.sh"
else
  echo "  RESULT: FAIL. chain id $CID, $FAIL address(es) with no code out of $COUNT."
  echo "  Under task 2.6 any claim resting on a failing address is CUT from the docs, not"
  echo "  footnoted."
fi
} | tee -a "$CODE_OUT" | tee -a "$CHAIN_OUT"

echo "written: $CHAIN_OUT and $CODE_OUT"
[ "$FAIL" -eq 0 ] && [ "$CID" = "1952" ]
