#!/usr/bin/env bash
# The onchain gates, run against the local chain from scripts/196-ci-anvil-up.sh.
#
# These are the gates that were going to be excluded from CI as "needs a funded key". They are not
# excluded. They deploy real contracts, submit real transactions and settle real trades, against a
# real EVM, with a throwaway account on a local chain.
#
# EVIDENCE PATH: evidence/phase18/ci-onchain.md
# PASS: every stage deploys or executes and the agent completes a full decide-gate-act cycle.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

# Environment written by 196. Sourced rather than recomputed so the two cannot drift.
[ -f /tmp/asml-ci.env ] || { echo "run scripts/196-ci-anvil-up.sh first"; exit 1; }
set -a
. /tmp/asml-ci.env
set +a
# lib.sh already ran with the defaults, so re-source it to pick up the overrides.
. ./lib.sh

OUT="$REPO/evidence/phase18/ci-onchain.md"
mkdir -p "$(dirname "$OUT")"

# THE DEPLOY SCRIPT REWRITES deployments.json, AND THAT FILE IS THE REAL TESTNET RECORD.
#
# Running these gates locally overwrote it with anvil addresses and an rpc of 127.0.0.1:8545. The
# damage was not obvious: the coordination API then asked REAL testnet for a venue that exists only
# on anvil, returned 503 on /thesis for 450 seconds straight, and looked like a slow warm-up rather
# than a clobbered file. The UI reads the same file, so it would have shown anvil addresses too.
#
# Backed up and restored on ANY exit, including a failing gate or an interrupt, because a gate that
# corrupts the working tree when it fails is worse than the failure.
# THREE files record the deployment, not one, and all three are rewritten by the deploy scripts:
#
#   deployments.json                     the machine-readable record every script reads
#   docs/verified/deployments.md         the human record the UI manifest is GENERATED from
#   ui-v2/public/data/deployments.json   the manifest the dashboard renders
#
# The first version of this guard backed up only the first, and a local run silently replaced the
# real testnet addresses in the other two. They are tracked files, so that would have been committed.
DEPLOY_JSON="$REPO/deployments.json"
GUARDED=(
  "$REPO/deployments.json"
  "$REPO/docs/verified/deployments.md"
  "$REPO/ui-v2/public/data/deployments.json"
  # Evidence the staged scripts regenerate. 112d rewrites this with whatever chain it ran against,
  # so a local run replaced a TESTNET evidence file with local-chain addresses while the file still
  # claimed to describe testnet. That is evidence corruption, not a stale artefact.
  "$REPO/evidence/phase8/per-user-limits.txt"
)
BACKUP_DIR="$(mktemp -d)"
for f in "${GUARDED[@]}"; do
  [ -f "$f" ] && cp "$f" "$BACKUP_DIR/$(echo "$f" | md5sum | cut -d' ' -f1)"
done

restore_deployments() {
  # Keep a copy of what was deployed locally BEFORE restoring, so the browser job can point the UI
  # manifest at it. Without this the restore erases the only record of the local addresses.
  [ -f "$DEPLOY_JSON" ] && cp "$DEPLOY_JSON" /tmp/asml-ci-deployments.json
  local restored=0
  for f in "${GUARDED[@]}"; do
    local b="$BACKUP_DIR/$(echo "$f" | md5sum | cut -d' ' -f1)"
    if [ -s "$b" ]; then cp "$b" "$f"; restored=$((restored + 1)); fi
  done
  rm -rf "$BACKUP_DIR"
  echo "restored $restored deployment record(s) to the pre-run state"
  echo "local-chain deployment kept at /tmp/asml-ci-deployments.json"
}
trap restore_deployments EXIT INT TERM

PASS=0; FAIL=0; ROWS=""
stage() { # label command...
  local label="$1"; shift
  local rc start end
  start=$(date +%s)
  "$@" > "/tmp/ci-stage.log" 2>&1
  rc=$?
  end=$(date +%s)
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1)); printf "  %-34s PASS  %ss\n" "$label" "$((end - start))"
    ROWS="$ROWS| \`$label\` | $((end - start))s | PASS |
"
  else
    FAIL=$((FAIL + 1)); printf "  %-34s FAIL exit %s\n" "$label" "$rc"
    tail -12 /tmp/ci-stage.log | sed 's/^/        /'
    ROWS="$ROWS| \`$label\` | - | **FAIL exit $rc** |
"
  fi
}

echo "=== chain: $(cast chain-id --rpc-url "$XLAYER_TESTNET_RPC") at $XLAYER_TESTNET_RPC ==="
echo "=== deployer: $DEPLOYER_ADDRESS ==="
echo

stage "deploy venue and guard"   bash 12-deploy-venue.sh
# AgentVault and FeeCollector are NOT deployed by 12. Without them the chain has no code at the
# vault address, and a withdrawal sent there succeeds trivially instead of reverting, which made the
# failure-path audit report "the chain accepted a withdrawal larger than the balance". An incomplete
# environment produces confident nonsense rather than an obvious error.
stage "deploy the vault"         bash 112c-vault-deploy.sh
stage "seed an executable book"  bash 136-seed-executable-book.sh
stage "agent decides and acts"   bash 18-agent-driven-run.sh
# A vault with no depositor cannot exercise a withdrawal path, so the browser gates get real state
# to act on rather than an empty contract.
stage "fund a depositor"         bash 112d-per-user-limits.sh

VERDICT=FAIL
[ "$FAIL" -eq 0 ] && [ "$PASS" -ge 5 ] && VERDICT=PASS

{
echo "# Onchain gates in CI, against a local chain"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **$VERDICT**"
echo
echo "Chain id \`$XLAYER_TESTNET_CHAIN_ID\` at \`$XLAYER_TESTNET_RPC\`, deployer"
echo "\`$DEPLOYER_ADDRESS\`, which is anvil's publicly known account 0 and funds nothing anywhere."
echo
echo "| stage | time | result |"
echo "|---|---|---|"
printf "%s" "$ROWS"
echo
echo "## Why this is not a skipped gate"
echo
echo "These deploy real contracts, submit real transactions and settle real trades against a real"
echo "EVM. What they do NOT do is prove anything about X Layer specifically: a fresh anvil chain has"
echo "no live order flow, no other participants and none of X Layer's OP Stack predeploys. The"
echo "mainnet claims rest on what chain 196 records, verified by"
echo "\`scripts/184-mainnet-reverify.sh\`, not on this."
echo
echo "No real key is involved. The alternative considered and rejected was putting the deployer"
echo "keystore in CI secrets, which would place a key holding real OKB one compromised action away"
echo "from being drained."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/196-ci-anvil-up.sh"
echo "bash scripts/197-ci-onchain-gates.sh"
echo '```'
} > "$OUT"

echo
echo "written: $OUT"
echo "VERDICT: $VERDICT  ($PASS passed, $FAIL failed)"
[ "$VERDICT" = PASS ]
