#!/usr/bin/env bash
# Task 9.5 gate: Pause and Withdraw always visible.
#
# THINKING: #22 inversion (the user's first fear is not "will it make money", it is "can I get my
# money back"), #29 margin-of-safety, #53 phenomenological.
#
# EVIDENCE PATH: evidence/phase9/exit-controls.md
# PASS: both controls are in the DOM and visible at every route and both viewport sizes, verified by
# measurement rather than by screenshot.
#
# FAKE WIN, quoted: "controls present but below the fold."
# COUNTER, quoted: "the audit asserts each control's bounding rect is inside the viewport."
#
# The audit goes further than the counter asks, because a rect test alone is not enough: a control
# can sit inside the viewport with an overlay painted on top of it and be entirely unclickable. So
# `elementFromPoint` at each control's centre must land on the control itself. That check is what
# distinguishes "visible" from "positioned".
#
# This script prepares the build and the harness. The measurements run inside the page
# (scripts/exit_controls_audit.js) driven by the Browser pane, because a bounding rect only means
# something in a real layout engine at a real viewport size. E11: the pane must be OPEN.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase9/exit-controls.md"
mkdir -p "$(dirname "$OUT")"

bash ./start-test-harness.sh < /dev/null 2>&1 | grep -E '^ui:|^signer:|error TS' || true
cp "$REPO/scripts/exit_controls_audit.js" "$REPO/ui-v2/dist/exit-audit.js"
cp "$REPO/scripts/landing_audit.js" "$REPO/ui-v2/dist/landing-audit.js"

echo
echo "harness ready. Measure in the Browser pane at 1280x720 and 390x844:"
echo "  fetch('/exit-audit.js').then(r=>r.text()).then(t=>eval(t))"
echo "Results are appended to $OUT."
