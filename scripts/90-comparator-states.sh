#!/usr/bin/env bash
# Task 5.4 RWA versus crypto comparator: capture all THREE states, live on chain.
#
# THINKING: #13 dialectical (one order, two markets, and the interesting artifact is the DISAGREEMENT
# and its cause), #19 critical thinking (the healthy state is the load-bearing one: without it the
# RWA layer reads as a global brake rather than a conditional one), #50 empirical.
#
# FAKE WIN this task names: showing only the refusing states. The healthy capture is a REQUIRED
# artifact and 5.5 asserts all three exist with the right verdicts.
#
# HOW THE STATES ARE PRODUCED: by moving the real RwaVault on chain 1952 with real transactions, then
# running the agent's own `sidebyside` mode against the moved state. Nothing is simulated and no
# verdict is written by this script; the risk engine produces every one of them.
#
#   healthy   fresh oracle, not paused, no divergence, no window nearby   -> both markets approve
#   paused    issuer pause set on the vault                              -> crypto approves, RWA refuses
#   diverged  market price observed 1000 bps away from the oracle        -> crypto approves, RWA refuses
#
# EVIDENCE PATH declared before code: evidence/phase5/comparator/{healthy,paused,diverged}.txt and
# ui-v2/public/data/comparator.json
# PASS: three states captured, each with both verdicts, and the healthy one showing BOTH approving.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT_DIR="$REPO/evidence/phase5/comparator"
mkdir -p "$OUT_DIR"
RPC="$XLAYER_TESTNET_RPC"
PASS_FILE="$PASSFILE"
# Addresses looked up BY NAME, not by line position. The first version took the 6th and 7th address
# in the file, which are BatchExecutor and a truncated market id, so every transaction went to the
# wrong contract and returned nothing. Positional parsing of a human-written table is exactly the kind
# of shortcut that produces confident wrong output: the script still printed verdicts.
addr_of() {
  grep -rhoE "$1[^0-9]*0x[0-9a-fA-F]{40}" "$REPO"/docs/verified/*.md \
    | grep -oE '0x[0-9a-fA-F]{40}' | head -1
}
VAULT=$(addr_of RwaVault)
RGUARD=$(addr_of RwaRiskGuard)

# Addresses are read from the verified deployments doc rather than typed here, so a redeploy cannot
# leave this script pointing at a dead contract while still printing verdicts.
{
echo "RWA versus crypto comparator, three states, task 5.4"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  vault:      ${VAULT:-NOT FOUND}"
echo "  rwa guard:  ${RGUARD:-NOT FOUND}"
} | tee "$OUT_DIR/run.txt"

if [ -z "$VAULT" ] || [ -z "$RGUARD" ]; then
  echo "  ABORT: could not read the RwaVault or RwaRiskGuard address from docs/verified/deployments.md"
  exit 1
fi

send() {
  cast send "$1" "$2" "${@:3}" --rpc-url "$RPC" --keystore "$KEYFILE" --password "$(cat "$PASS_FILE")" \
    --json 2>/dev/null | grep -oE '"status":"0x[01]"' | head -1
}

capture() {
  local name="$1"
  echo "  capturing state: $name" | tee -a "$OUT_DIR/run.txt"
  cd "$REPO"
  ./target/release/asml sidebyside > "$OUT_DIR/$name.txt" 2>&1
  cd "$(dirname "$0")"
  grep -E "CRYPTO market|RWA market|APPROVED|REFUSED|DIVERGENT|rwa vault:|Identical order" \
    "$OUT_DIR/$name.txt" | head -12 | sed 's/^/    /' | tee -a "$OUT_DIR/run.txt"
}

# ---- HEALTHY ----------------------------------------------------------------
{
echo
echo "## STATE 1: healthy. Both markets should approve."
echo "   This is the state the task calls REQUIRED: an RWA layer that refuses in every state is a"
echo "   global brake, not a risk control, and only the healthy capture distinguishes the two."
} | tee -a "$OUT_DIR/run.txt"
echo "  touchOracle:            $(send "$VAULT" 'touchOracle()')" | tee -a "$OUT_DIR/run.txt"
echo "  setPaused(false):       $(send "$VAULT" 'setPaused(bool)' false)" | tee -a "$OUT_DIR/run.txt"
echo "  observeMarketPrice(1x): $(send "$RGUARD" 'observeMarketPrice(uint256)' 1000000000000000000)" | tee -a "$OUT_DIR/run.txt"
capture healthy

# ---- PAUSED -----------------------------------------------------------------
{
echo
echo "## STATE 2: issuer paused. Crypto approves, RWA refuses."
} | tee -a "$OUT_DIR/run.txt"
echo "  setPaused(true):        $(send "$VAULT" 'setPaused(bool)' true)" | tee -a "$OUT_DIR/run.txt"
capture paused

# ---- DIVERGED ---------------------------------------------------------------
{
echo
echo "## STATE 3: oracle and market diverge by 1000 bps against a 300 bps policy."
} | tee -a "$OUT_DIR/run.txt"
echo "  setPaused(false):       $(send "$VAULT" 'setPaused(bool)' false)" | tee -a "$OUT_DIR/run.txt"
echo "  observeMarketPrice(1.10x): $(send "$RGUARD" 'observeMarketPrice(uint256)' 1100000000000000000)" | tee -a "$OUT_DIR/run.txt"
capture diverged

# ---- RESTORE ----------------------------------------------------------------
# Leave the instrument HEALTHY. A demo that ends with the vault paused would make every later run
# look like a refusal, and the next reader would have no way to know a script did it.
{
echo
echo "## Restoring the instrument to healthy, so later runs are not distorted by this one"
} | tee -a "$OUT_DIR/run.txt"
echo "  setPaused(false):       $(send "$VAULT" 'setPaused(bool)' false)" | tee -a "$OUT_DIR/run.txt"
echo "  observeMarketPrice(1x): $(send "$RGUARD" 'observeMarketPrice(uint256)' 1000000000000000000)" | tee -a "$OUT_DIR/run.txt"
echo "  touchOracle:            $(send "$VAULT" 'touchOracle()')" | tee -a "$OUT_DIR/run.txt"

# ---- JSON for the UI --------------------------------------------------------
/home/zulab/.asml-venv/bin/python "$REPO/scripts/comparator_json.py" 2>&1 | tee -a "$OUT_DIR/run.txt"
RC=${PIPESTATUS[0]}

{
echo
echo "## Verdict, task 5.4"
if [ "${RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. Three states captured from the live chain, verdicts produced by the risk"
  echo "  engine rather than written by this script. UI data at ui-v2/public/data/comparator.json."
else
  echo "  RESULT: FAIL, the three states were not all captured with both verdicts."
fi
} | tee -a "$OUT_DIR/run.txt"

echo "written: $OUT_DIR/run.txt"
exit "${RC:-1}"
