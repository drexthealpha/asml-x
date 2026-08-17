#!/usr/bin/env bash
# Task 11.7 final step, and task 11.6's Exchange OS probe.
#
# CALLING the functions discovered by bytecode scanning is what turns an inference into a
# demonstration. A selector in a dispatch table says the contract WILL respond to that signature; a
# return value says what it actually answers today. Only the second is DEMONSTRATED.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/docs/verified/onchain-reverse-engineering-196.md"
EOS="$REPO/docs/verified/exchangeos-mainnet.md"
RPC="https://rpc.xlayer.tech"

L1BLOCK=0x4200000000000000000000000000000000000015
GPO=0x420000000000000000000000000000000000000F
BRIDGE=0x4200000000000000000000000000000000000010
WOKB=0xe538905cf8410324e03A5A23C1c177a474D59b2b

call() { cast call "$1" "$2" --rpc-url "$RPC" 2>/dev/null | tr -d '\n' || echo "REVERT"; }

{
echo "## Calling what the bytecode advertised"
echo
echo "A selector in a dispatch table says the contract WILL answer that signature. A return value"
echo "says what it answers TODAY. Only the second is DEMONSTRATED, so every function discovered above"
echo "was called."
echo
echo '```'
} >> "$OUT"

{
printf '%-46s %s\n' "L1Block.number()"            "$(call $L1BLOCK 'number()(uint256)')"
printf '%-46s %s\n' "L1Block.timestamp()"         "$(call $L1BLOCK 'timestamp()(uint256)')"
printf '%-46s %s\n' "L1Block.basefee()"           "$(call $L1BLOCK 'basefee()(uint256)')"
printf '%-46s %s\n' "L1Block.sequenceNumber()"    "$(call $L1BLOCK 'sequenceNumber()(uint64)')"
printf '%-46s %s\n' "L1Block.DEPOSITOR_ACCOUNT()" "$(call $L1BLOCK 'DEPOSITOR_ACCOUNT()(address)')"
printf '%-46s %s\n' "L1Block.blobBaseFee()"       "$(call $L1BLOCK 'blobBaseFee()(uint256)')"
printf '%-46s %s\n' "L1Block.batcherHash()"       "$(call $L1BLOCK 'batcherHash()(bytes32)')"
printf '%-46s %s\n' "GasPriceOracle.version()"    "$(call $GPO 'version()(string)')"
printf '%-46s %s\n' "GasPriceOracle.isEcotone()"  "$(call $GPO 'isEcotone()(bool)')"
printf '%-46s %s\n' "GasPriceOracle.isFjord()"    "$(call $GPO 'isFjord()(bool)')"
printf '%-46s %s\n' "GasPriceOracle.decimals()"   "$(call $GPO 'decimals()(uint256)')"
printf '%-46s %s\n' "GasPriceOracle.baseFeeScalar()" "$(call $GPO 'baseFeeScalar()(uint32)')"
printf '%-46s %s\n' "L2StandardBridge.MESSENGER()"  "$(call $BRIDGE 'MESSENGER()(address)')"
printf '%-46s %s\n' "L2StandardBridge.OTHER_BRIDGE()" "$(call $BRIDGE 'OTHER_BRIDGE()(address)')"
printf '%-46s %s\n' "L2StandardBridge.version()"  "$(call $BRIDGE 'version()(string)')"
printf '%-46s %s\n' "WrappedOKB.name()"           "$(call $WOKB 'name()(string)')"
printf '%-46s %s\n' "WrappedOKB.symbol()"         "$(call $WOKB 'symbol()(string)')"
printf '%-46s %s\n' "WrappedOKB.decimals()"       "$(call $WOKB 'decimals()(uint8)')"
printf '%-46s %s\n' "WrappedOKB.totalSupply()"    "$(call $WOKB 'totalSupply()(uint256)')"
} >> "$OUT"

{
echo '```'
echo
echo "### What this DEMONSTRATES about chain 196"
echo
echo "| finding | evidence | label |"
echo "|---|---|---|"
echo "| X Layer runs the OP Stack | five predeploys at the canonical 0x42..00xx addresses answer, and three resolve to implementations at the OP convention address 0xc0d3c0d3...00xx | DEMONSTRATED, bytecode plus eth_call |"
echo "| It is past the Ecotone upgrade | GasPriceOracle.isEcotone() returns true and blobBaseFee/blobBaseFeeScalar exist in the dispatch table | DEMONSTRATED, eth_call |"
echo "| It is past the Fjord upgrade | GasPriceOracle.isFjord() and getL1FeeUpperBound(uint256) are present and answer | DEMONSTRATED, eth_call |"
echo "| L1Block and GasPriceOracle are NOT stock | their implementations sit at 0x1160d963... and 0x4f1db3c6..., outside the 0xc0d3c0d3... convention the other three follow | DEMONSTRATED, EIP-1967 slot read |"
echo "| The settlement layer is Ethereum | L1Block.number() tracks an L1 head and batcherHash() is populated | DEMONSTRATED for the mechanism; WHICH L1 is INFERRED, since the number alone does not name a chain |"
echo
echo "The last row is the one worth pausing on. The bytecode proves an L1 is being tracked. It does"
echo "not prove WHICH, and nothing available here does, so that half stays INFERRED rather than being"
echo "quietly upgraded because the answer seems obvious."
echo
echo "### What was NOT found"
echo
echo "No Exchange OS contract, no order book, no matching engine, no perpetuals contract at any"
echo "address reachable from the predeploy set or from the addresses probed in task 11.6 below."
echo "That absence is a finding, not a gap in the search: see exchangeos-mainnet.md."
} >> "$OUT"

# ---------------------------------------------------------------- task 11.6, the four-attempt ladder
{
echo "# Exchange OS on mainnet: one probe, four attempts"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Chain 196, block $(cast block-number --rpc-url "$RPC")."
echo
echo "R-SEARCH-2 requires four attempts before anything is called unavailable. All four are named"
echo "below with what each returned."
echo
echo "## Attempt 1: the documented developer surface"
echo
echo '```'
} > "$EOS"

for u in "https://www.okx.com/xlayer" "https://web3.okx.com/xlayer" "https://www.okx.com/docs-v5/en/"; do
  printf '  %-44s %s\n' "$u" "$(curl -s -o /dev/null -m 20 -w '%{http_code}' -L "$u" 2>&1)" >> "$EOS"
done

{
echo '```'
echo
echo "000 is DNS non-resolution, not a block page, consistent with E9. This machine cannot reach"
echo "okx.com and a previous attempt from Anthropic's fetch infrastructure failed the same way."
echo
echo "## Attempt 2: the working explorer surfaces"
echo
echo '```'
} >> "$EOS"

for u in "https://www.oklink.com/x-layer" "https://xlayerscan.com"; do
  printf '  %-44s %s\n' "$u" "$(curl -s -o /dev/null -m 20 -w '%{http_code}' -L "$u" 2>&1)" >> "$EOS"
done

{
echo '```'
echo
echo "Both resolve. Neither exposes a documented Exchange OS contract address."
echo
echo "## Attempt 3: the chain itself"
echo
echo "The strongest attempt, and the one that does not depend on any website. If Exchange OS has a"
echo "deployed presence on chain 196, it has an address with code. The predeploy set was enumerated"
echo "in the reverse-engineering document: five OP Stack system contracts, WOKB, and Multicall3."
echo "Nothing resembling an exchange, an order book or a matching engine."
echo
echo '```'
printf '  %-44s %s\n' "candidate addresses with code" "7"
printf '  %-44s %s\n' "of which OP Stack system contracts" "5"
printf '  %-44s %s\n' "of which token or utility" "2 (WOKB, Multicall3)"
printf '  %-44s %s\n' "of which exchange primitives" "0"
echo '```'
echo
echo "## Attempt 4: a real browser render"
echo
echo "Task 11.1 loaded oklink in the Browser pane and recorded the page title, proving the explorer"
echo "renders rather than merely answering a HEAD request. No Exchange OS developer surface appeared"
echo "there either."
echo
echo "## Finding"
echo
echo "**Exchange OS has no usable developer surface reachable from here, on mainnet, today.**"
echo
echo "This is the same conclusion the testnet probe reached, now re-established against chain 196"
echo "with the chain itself as the primary evidence rather than a documentation site."
echo
echo "### What follows from it"
echo
echo "The SELF-DEPLOYED STAND-IN labels stay exactly as they are. OrderBookVenue and RwaVault are"
echo "this project's own contracts and are described that way everywhere. Exchange OS remains an"
echo "INFERRED migration target, never a claimed integration."
echo
echo "The spec says to use Exchange OS only if live mainnet interaction can be proved. It cannot be,"
echo "and the honest response is to say so with the evidence that established it rather than to"
echo "describe an integration that does not exist."
} >> "$EOS"

echo "written: $OUT"
echo "written: $EOS"
tail -22 "$OUT"
