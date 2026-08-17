#!/usr/bin/env bash
# Task 8.1: verify custody, withdrawal-griefing and pause-authority patterns BEFORE writing the vault.
#
# THINKING: #49 skeptical (a custody contract is where "it looks right" costs someone their money,
# and the failure is silent until it is total), #29 margin-of-safety (design for the case where the
# operator key is hostile, not merely absent), #60 map-territory (what have auditors actually FOUND
# in shipped vaults, versus what a tutorial recommends).
#
# EVIDENCE PATH declared before code: evidence/phase8/vault-research.md
# PASS: two primary sources with links, and one named pattern REJECTED with the specific property
# that made it wrong here.
# FAKE WIN, quoted from TASKS.md: "research that concludes exactly what was already planned."
# COUNTER: "the rejected pattern must be one that was genuinely considered." ERC-4626 was the default
# choice for this contract until this research, and the section below records what changed my mind.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase8/vault-research.md"
mkdir -p "$(dirname "$OUT")"

probe() {
  printf '  %-60s %s\n' "$1" "$(curl -s -o /dev/null -m 25 -w '%{http_code}' -L "$1" 2>&1)"
}

{
echo "# Vault custody, withdrawal griefing and pause authority, task 8.1"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')."
echo
echo '## Source reachability, checked rather than assumed'
echo '```'
} > "$OUT"

{
probe "https://scsfg.io/hackers/griefing/"
probe "https://smartcontractshacking.com/glossary/pausable"
probe "https://www.chainsecurity.com/security-audit/morpho-vault-v2"
} >> "$OUT"

cat >> "$OUT" <<'MD'
```

## Primary sources used

1. **Smart Contract Security Field Guide, griefing**, scsfg.io/hackers/griefing.
   Three concrete mechanisms, each an attack that costs the attacker money and gains them nothing,
   which is why they get designed out rather than priced in:
   - **Withdrawal delay reset.** A `DelayedWithdrawal` contract let anyone call `deposit` with 1 wei
     to reset `lastDeposit`, so a legitimate beneficiary could be kept permanently short of the
     delay. The lesson is not "add a check"; it is that ANY timer a third party can reset is a
     denial-of-service primitive.
   - **External call failure blocking.** A relayer marked data as executed in an `executed` mapping
     even when the inner call failed, so nobody could ever resubmit it. State that records intent
     rather than outcome is the bug.
   - **Gas griefing via the 63/64 rule.** An adversary supplies enough gas for the outer call and
     not the inner one, so the transaction "succeeds" while the work does not happen.

2. **Pausable, definition and audit notes**, smartcontractshacking.com/glossary/pausable.
   The audit question it poses is the one that matters here, quoted: whether users "can withdraw,
   repay, or reduce risk while paused when the protocol design requires it." It names
   "Pause blocks withdrawals or repayment without a safe escape path" as a major red flag, flags
   "Pauser and unpauser are the same hot EOA" as an anti-pattern, and notes that a pause can
   "create governance griefing if the pauser is compromised."

## What this project adopts, and which source forced each choice

**PAUSE NEVER BLOCKS WITHDRAWAL.** This is the direct consequence of source 2. In `AgentVault`,
`pause()` stops the AGENT from acting on a depositor's funds and has no effect on that depositor's
`withdraw()`. A pause that could trap funds would convert the safety feature into the attack, which
is exactly the red flag named above. Task 8.4 proves this as a theorem rather than asserting it:
a depositor can withdraw their full balance whether paused or not.

**THE PAUSER IS THE DEPOSITOR, NOT AN OPERATOR ROLE.** Source 2's anti-pattern is a hot EOA holding
both pause and unpause. The usual fix is a multisig plus a timelock, and that is the right fix for a
protocol-wide pause. It is the wrong fix here, because the thing being paused is not the protocol,
it is one user's own agent. Per-depositor pause has no shared authority to compromise: there is no
key that can pause everyone, so there is no governance-griefing surface to defend. This is a case
where the standard mitigation is unnecessary because the standard risk was designed out.

**NO TIMER A THIRD PARTY CAN TOUCH.** From source 1's withdrawal-delay reset. `AgentVault` has no
withdrawal delay, no cooldown, and no timestamp that any caller can advance. Withdrawal is
synchronous. There is nothing to reset because there is nothing to wait for.

**OUTCOME, NOT INTENT, IS RECORDED.** From source 1's `executed` mapping. Balance changes are
written from measured deltas and the transfer is checked, so a failed movement cannot leave state
claiming it happened.

**CHECKS-EFFECTS-INTERACTIONS ON WITHDRAW,** with the balance zeroed before the token moves. The
reentrancy path in a vault holding a third-party token is through the TOKEN's transfer hook during
withdrawal, which is the case ADR-006's Phase 7 research already identified.

## PATTERN CONSIDERED AND REJECTED: ERC-4626 share-based accounting

This was the intended design before this research, which is the only reason recording the rejection
is worth anything. ERC-4626 is the standard for tokenised vaults, it is what a reviewer expects to
see, and choosing something else needs a reason better than preference.

**The reason is that shares price a pool, and there is no pool here.** ERC-4626 exists so that N
depositors can share ONE strategy and one asset balance, with shares tracking each depositor's
proportional claim on a commingled pot. ASML-X is the opposite arrangement: each depositor sets their
own limits (task 8.3), the agent trades each deposit against those limits, and outcomes are
per-depositor by construction. Shares over that structure produce one of two failures:

- **If the pot is genuinely commingled,** a share price socialises every outcome. A depositor who set
  a 10 unit limit would absorb losses generated under someone else's 1000 unit limit. Per-user limits
  would then be theatre, since the risk a user actually carries would be the pool's, not their own.
- **If it is not commingled,** per-depositor balances have to be tracked anyway, and the share layer
  becomes arithmetic that can drift from the balances underneath it. Two representations of one fact.

It also imports the first-depositor inflation attack, which the ERC-4626 risk catalogue cited in
task 7.1 lists first, for no benefit that survives the paragraph above.

**So `AgentVault` uses direct per-depositor balances.** `balanceOf[depositor]` is the depositor's
tokens, full stop. No share price, no conversion, no rounding direction to get wrong, and no
inflation attack. The README will say "per-depositor balances, not ERC-4626 shares", with this file
as the reason, because silently omitting the standard would read as not knowing about it.

**Revisit condition:** if ASML-X ever runs one strategy over pooled capital, ERC-4626 becomes correct
and this decision should be reversed. It is not that today.

## SECOND PATTERN CONSIDERED AND REJECTED: a withdrawal queue with a delay

Considered because a delay is the standard defence against an operator who front-runs user exits, and
because it would let an in-flight agent action settle before funds leave.

Rejected on source 1's evidence: a delay is a timer, timers are griefing surfaces, and the specific
`DelayedWithdrawal` finding shows how cheaply one is reset. More decisively, a delay contradicts the
property this phase exists to establish. A user who wants out must be able to get out NOW, and a
vault that answers "in 24 hours" has not solved custody, it has renamed it. The in-flight concern is
handled structurally instead: the agent never holds user funds, so there is no in-flight state that a
withdrawal can interrupt.

## What could still go wrong, and where it is caught

| risk | where it is caught |
|---|---|
| agent or owner withdraws a user's funds | 8.2 tests from three different keys; 8.4 theorem |
| a depositor cannot exit while paused | 8.4 theorem: withdrawal is proved independent of pause |
| sum of balances exceeds the vault's token holdings | 8.4 solvency theorem |
| a limit is enforced offchain only | 8.3 proves the onchain revert with a real testnet tx |
| a test passes because its precondition is unreachable | 8.5 mutation; a vacuous property survives everything |
| pause is demonstrated on an idle agent | 8.7 requires the pause to land mid-cycle, proven by block numbers |
MD

echo "written: $OUT"
grep -c "^" "$OUT" | sed 's/^/lines: /'
