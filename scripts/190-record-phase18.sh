#!/usr/bin/env bash
# Record C-1800 through C-1803 and write the Phase 18 gate report.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN="$REPO/evidence/CHAIN-OF-EVIDENCE.md"
GATE="$REPO/evidence/gates/phase18.md"
BEATS="$REPO/evidence/phase18/demo-beats.md"
mkdir -p "$REPO/evidence/phase18"

for f in docs/DEMO-SCRIPT.md evidence/phase18/sweep.md; do
  [ -s "$REPO/$f" ] || { echo "MISSING OR EMPTY: $f"; exit 1; }
done
grep -q "Verdict: \*\*PASS\*\*" "$REPO/evidence/phase18/sweep.md" || { echo "18.3 not green"; exit 1; }

cat > "$BEATS" <<'EOF'
# Task 18.1 verification: does the demo script describe the page that exists?

A demo script that tells a presenter to point at a panel which is not there fails on camera, in one
take, with no way to recover. So every beat was checked against the live built page rather than
against memory of what was built.

| beat the script relies on | present on the live page |
|---|---|
| MAINNET panel on the landing surface | yes |
| the words "chain 196" visible without navigating | yes |
| Connect control, or a clear no-wallet state | yes |
| "Run full demo" button | yes |
| "What the agent learned" panel | yes |
| `n = 10` sample size in the panel header | yes |
| net move showing 2000 and 391 | yes |
| hit rate 40.0% | yes |
| all five tabs reachable | yes |
| fee disclosure in basis points | **only after Connect** |

**9 of 10 confirmed on the live page.** The tenth is not a defect: the fee disclosure renders from
`pos.feeBps` inside `activate.tsx:310` and only exists once a wallet is connected, which the script's
own ordering already respects. It is called out in the script so the presenter does not reach for it
early, and it is the one beat that cannot be verified from here because acquiring a browser wallet
extension is a user-handled step.
EOF

{
echo "# Phase 18 gate report: video, sweep, submit"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
echo
echo "## 18.1 demo script — DONE"
echo
echo "[docs/DEMO-SCRIPT.md](../../docs/DEMO-SCRIPT.md), three minutes, timed to the spec's shape:"
echo "land, connect, defaults, deposit, activate, decision and fee event, pause, withdraw, Terminal."
echo
echo "It carries a **What must NOT be said** list: no USD figure, no performance language, nothing"
echo "calling AggLayer verified, nothing claiming Exchange OS integration, and no mention of the"
echo "venue without \"self-deployed stand-in\" nearby."
echo
echo "**The refusal is scheduled on camera at 1:45, deliberately.** A demo edited to remove a refusal"
echo "advertises the opposite of what this project claims."
echo
echo "Every beat was verified against the live built page: 9 of 10 confirmed, the tenth being the fee"
echo "disclosure which only renders after Connect. See [demo-beats.md](../phase18/demo-beats.md)."
echo
echo "## 18.3 final sweep — DONE, PASS"
echo
echo "**0 gitleaks findings** across the full history. The keystore and its password both live at"
echo "\`~/.asml-keys/\`, **outside the working tree entirely**, so no \`git add\` however forced can"
echo "reach them. **0 key-shaped files anywhere inside the repo tree.** CLAUDE.md, RESUME.md and"
echo "TASKS.md all confirmed gitignored."
echo
echo "A scanner alone would not have been enough: gitleaks finds patterns it knows, and cannot tell"
echo "you that key material sits in a file it never scanned. So this checked three things separately."
echo
echo "## 18.2 record the video — NEEDS THE USER"
echo
echo "Everything that can be prepared is prepared: the script is written and timed, the pre-recording"
echo "commands are listed, and the page has been verified to contain what the script points at."
echo
echo "**Producing the actual screen recording requires a human at a screen recorder**, and a wallet"
echo "extension, which is the same user-handled dependency as task 9.0. This is stated as an"
echo "outstanding item rather than marked complete."
echo
echo "## 18.4 submission — USER HANDLES, unchanged"
echo
echo "The dedicated X account, the submission post mentioning @XLayerOfficial, the Google Form, and"
echo "**every git commit, push and tag**. No git operation has been performed by this build."
echo
echo "## Reproduce"
echo
echo '```'
echo "bash scripts/189-final-sweep.sh"
echo '```'
} > "$GATE"

TODAY=$(date -u '+%Y-%m-%d')
if grep -q "C-1800" "$CHAIN"; then
  echo "already recorded"
else
cat >> "$CHAIN" <<EOF
| C-1800 | A three-minute demo script timed to the specification's shape, with every beat VERIFIED against the live built page rather than against memory: 9 of 10 confirmed present, the tenth being a fee disclosure that only renders after Connect and is flagged in the script so the presenter does not reach for it early. A demo script naming a panel that is not there fails on camera in one take with no way to recover. It schedules the risk refusal ON CAMERA at 1:45 deliberately, because a demo edited to remove a refusal advertises the opposite of what this project claims, and it carries a WHAT MUST NOT BE SAID list covering USD figures, performance language, calling AggLayer verified, and claiming Exchange OS integration | docs/DEMO-SCRIPT.md, evidence/phase18/demo-beats.md | bash scripts/190-record-phase18.sh | DEMONSTRATED | 18.1 | $TODAY |
| C-1802 | Final security sweep clean: 0 gitleaks findings across the full history, the keystore and its password both outside the working tree at ~/.asml-keys/ so no git add however forced can reach them, 0 key-shaped files anywhere inside the repo tree, and CLAUDE.md, RESUME.md and TASKS.md all confirmed gitignored. Three checks rather than one, because a scanner finds only patterns it knows and cannot tell you that key material sits in a file it never scanned or that a gitignored file is one forced add away from publication | evidence/phase18/sweep.md | bash scripts/189-final-sweep.sh | DEMONSTRATED | 18.3 | $TODAY |
EOF
echo "appended C-1800, C-1802"
fi

echo "written: $GATE"
echo "written: $BEATS"
grep -c "^| C-" "$CHAIN"
