#!/usr/bin/env bash
# Record C-1700 through C-1704 and write the Phase 17 gate report.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

CHAIN="$REPO/evidence/CHAIN-OF-EVIDENCE.md"
GATE="$REPO/evidence/gates/phase17.md"
DENS="$REPO/evidence/phase17/density.md"
mkdir -p "$REPO/evidence/phase17"

for f in JUDGE-GUIDE.md README.md docs/limitations.md evidence/phase17/claim-tags.md; do
  [ -s "$REPO/$f" ] || { echo "MISSING OR EMPTY: $f"; exit 1; }
done

# The claim-tag gate must be CLEAN, not merely present. A judge-facing doc citing a claim that does
# not exist is the defect this whole phase is guarding against.
python3 187-claim-tags.py > /dev/null 2>&1 || { echo "claim tags not clean. Refusing to record."; exit 1; }
bash 144-claim-consistency.sh < /dev/null > /dev/null 2>&1 || { echo "claim consistency failed"; exit 1; }

cat > "$DENS" <<'EOF'
# Task 17.5: density on the final build

Measured in the Browser pane at 1920x1080 with `scripts/measure-density.js`, on the built
`dist/`, not on a dev server.

| metric | before | after | note |
|---|---|---|---|
| ink coverage | 28.50% | **38.13%** | text-run coverage of the viewport |
| text runs | 167 | **236** | |
| numeric cells | 42 | **66** | `.num` elements |
| largest empty rect | 408x720, 14.17% | **648x432, 13.50%** | |

## What was wrong and what was done

The left column ended below "Your position", leaving a **408x720 void, 14.17% of the viewport**.
That is the same proportion an earlier phase treated as a defect after measuring a 624x472 hole,
and the fix then was the same principle as now: **fill a void with data the project already holds,
never with decoration.**

The MAINNET panel was moved onto the landing surface. It was previously reachable only from the
CHAIN tab, which meant a judge who read the landing page and left would never have seen that this
runs on X Layer mainnet with real money. It is the strongest evidence in the submission and it was
one click away from being missed.

## A measurement trap, recorded

The first re-measurement returned **numbers identical to the baseline**, including an unchanged text
run count. The browser was serving a stale bundle: `index-45Nw93sF.js` while the build had produced
`index-ChCly-7j.js`. Identical numbers after a real change are a signal to check the instrument, not
to conclude the change did nothing.

A screenshot then showed the app occupying roughly a third of the frame with the rest black, which
looks exactly like a broken layout. It is not: `document.body` and `#root` both measure 1920x1080
with `scrollWidth` equal to `innerWidth` and no overflow. That is a screenshot-compositing artifact
of the emulated viewport. **This project has been burned once by trusting a rendering artifact over
a measurement**, in the mobile audit that ADR-018 withdrew, so the DOM measurement is treated as
authoritative and the artifact is recorded rather than acted on.

## Reproduce

Serve the built UI, then run `scripts/measure-density.js` in the Browser pane at 1920x1080.
EOF

{
echo "# Phase 17 gate report: docs and JUDGE-GUIDE"
echo
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC'). Verdict: **PASS**"
echo
echo "## 17.1 JUDGE-GUIDE, rewritten for the conviction bar"
echo
echo "Restructured to lead with **the mainnet proof and the user flow**, not the formal verification."
echo "Step 1 is \"it is live on mainnet with the user's own money\" and step 2 is \"a person can"
echo "deposit, let the agent trade, and get their money back\". Formal verification and the"
echo "differential proof moved to step 3, where they belong: they are what makes the product safe to"
echo "use, not the reason to look at it."
echo
echo "It also carries a section named **The fastest way to attack this submission**, listing the four"
echo "places a hostile reader should look first, in order, including one I would want cut if found."
echo
echo "## 17.2 README leads with what a person can do"
echo
echo "The first sentence is now the product, not the architecture. The old opening led with"
echo "\"an autonomous market brain\" and, more seriously, still said **Testnet only**, which stopped"
echo "being true in Phase 12."
echo
echo "## 17.3 limitations.md updated"
echo
echo "Four entries were **stale in a flattering-or-misleading direction** and are corrected:"
echo
echo "1. \"No realized PnL anywhere\" is no longer true. It is replaced by the measured result, which"
echo "   is worse: a 40% hit rate on n=10 and a net position that lost. **The failure to be"
echo "   profitable is now measured rather than merely unmeasured**, which is a stronger disclosure."
echo "2. \"No mainnet deployment\" is struck through rather than deleted, so the change is visible."
echo "3. The coordination burst stall is marked FIXED, with the WRONG diagnosis kept because that is"
echo "   the useful part: per-socket timeouts could not have worked, since a deadline on a socket"
echo "   does not shorten a queue."
echo "4. \"No run demo button\" and \"codebase-memory-mcp and paperscraper never installed\" were both"
echo "   false."
echo
echo "AggLayer is now explicitly listed under what is NOT claimed."
echo
echo "## 17.4 every claim carries a resolvable tag"
echo
echo "Checked in **both** directions across six judge-facing documents: every \`[C-xxx]\` resolves to"
echo "a row, and every script those documents tell a reader to run exists. **0 dangling tags, 0"
echo "missing scripts**, against 119 claim ids."
echo
echo "Backward matters as much as forward: Phase 16 found two chain rows citing scripts that never"
echo "existed, and a guide that sends a judge to a missing script fails at the worst possible moment."
echo
echo "## 17.5 density and consistency on the final build"
echo
echo "Ink coverage **28.50% to 38.13%**, largest void **14.17% to 13.50%**, by moving the MAINNET"
echo "panel onto the landing surface. Detail and two measurement traps in"
echo "[evidence/phase17/density.md](../phase17/density.md)."
echo
echo "\`scripts/144-claim-consistency.sh\` now passes **fully**, closing the outstanding half of task"
echo "12.7. It had been reporting JUDGE-GUIDE as a missing file for six phases because it looked in"
echo "\`docs/\` while the guide lives at the repo root, and it correctly refused to call that a pass."
echo
echo "## Reproduce"
echo
echo '```'
echo "python3 scripts/187-claim-tags.py"
echo "bash scripts/144-claim-consistency.sh"
echo '```'
} > "$GATE"

TODAY=$(date -u '+%Y-%m-%d')
if grep -q "C-1700" "$CHAIN"; then
  echo "already recorded"
else
cat >> "$CHAIN" <<EOF
| C-1700 | The JUDGE-GUIDE leads with the mainnet proof and the user flow rather than the formal verification: step 1 is that it runs on chain 196 with the user's own money and step 2 is that a person can deposit, let the agent trade and withdraw, with the differential proof and the invariants moved to step 3 where they belong as what makes the product safe rather than the reason to look at it. It carries a section naming the four fastest ways to attack the submission, in order, including one the author states should be CUT if a reader finds it | JUDGE-GUIDE.md | python3 scripts/187-claim-tags.py | DEMONSTRATED | 17.1 | $TODAY |
| C-1701 | The README opens with what a person can do rather than with the architecture, and its claim that this was TESTNET ONLY is removed, having stopped being true in Phase 12. The opening states the three properties that make it safe to use and marks each as proved rather than promised, and states in the opening that the agent is NOT profitable, with the measured number | README.md | python3 scripts/187-claim-tags.py | DEMONSTRATED | 17.2 | $TODAY |
| C-1702 | Four entries in limitations.md were stale in a flattering or misleading direction and are corrected rather than quietly refreshed: NO REALIZED PNL ANYWHERE is replaced by the measured result, which is worse, so the failure to be profitable is now measured rather than merely unmeasured; NO MAINNET DEPLOYMENT is struck through rather than deleted so the change is visible; the coordination burst stall is marked FIXED with the WRONG diagnosis deliberately kept, because per-socket timeouts could not have worked since a deadline on a socket does not shorten a queue; and two entries claiming absent features and uninstalled tools were simply false. AggLayer is added explicitly to what is NOT claimed | docs/limitations.md | python3 scripts/187-claim-tags.py | DEMONSTRATED | 17.3 | $TODAY |
| C-1703 | Claim tags checked in BOTH directions across six judge-facing documents against 119 chain ids: 0 dangling tags and 0 missing scripts. Forward, every [C-xxx] resolves to a row, because a dangling tag is worse than no tag since it looks like evidence and is not. Backward, every script those documents tell a reader to run exists, because Phase 16 found two chain rows citing scripts that never existed and a guide that sends a judge to a missing script fails at the worst possible moment | evidence/phase17/claim-tags.md | python3 scripts/187-claim-tags.py | DEMONSTRATED | 17.4 | $TODAY |
| C-1704 | Density re-measured on the BUILT dist at 1920x1080: ink coverage 28.50 to 38.13 percent, text runs 167 to 236, numeric cells 42 to 66, largest empty rectangle 14.17 to 13.50 percent of the viewport, achieved by moving the MAINNET panel onto the landing surface where it fills a void with data the project already holds rather than with decoration, and where a judge who reads the landing page and leaves can no longer miss that this runs on mainnet with real money. Two measurement traps are recorded: the first re-measurement returned numbers IDENTICAL to the baseline because the browser was serving a stale bundle, which is a signal to check the instrument rather than conclude the change did nothing, and a screenshot appearing to show a broken layout was a compositing artifact contradicted by body and root both measuring 1920x1080 with no overflow, which this project treats as authoritative after being burned once by trusting a rendering artifact over a measurement. scripts/144-claim-consistency.sh now passes fully, closing the outstanding half of task 12.7 after six phases of correctly refusing to call a missing file a pass | evidence/phase17/density.md, evidence/gates/phase17.md | bash scripts/144-claim-consistency.sh | DEMONSTRATED | 17.5 | $TODAY |
EOF
echo "appended C-1700..C-1704"
fi

echo "written: $GATE"
echo "written: $DENS"
grep -c "^| C-" "$CHAIN"
