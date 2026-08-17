#!/usr/bin/env bash
# Task 9.2 gate: the landing surface.
#
# THINKING: #12 design thinking, #37 visual/spatial, #53 phenomenological.
#
# EVIDENCE PATH: evidence/phase9/landing.md
# PASS: zero blocking empty states, and the primary action is reachable without scrolling at
# 1280x720 and at 390x844.
#
# FAKE WIN, quoted: "a beautiful landing page that hides the product behind a second click."
# COUNTER, quoted: "the click counter in 9.4 counts from this screen." The personal view is therefore
# the FIRST tab and the default, not a fifth tab appended after the existing four, so a cold visitor
# is already on it and the count starts at zero.
#
# This script prepares the build and the measurement harness. The measurements themselves run inside
# the page (scripts/landing_audit.js) driven by the Browser pane, because a bounding rect is only
# meaningful in a real layout engine at a real viewport size. E11: the pane must be OPEN or
# requestAnimationFrame never fires and every measurement hangs.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase9/landing.md"
mkdir -p "$(dirname "$OUT")"

cd "$REPO/ui-v2"
npm run build 2>&1 | tail -3
cp -r public/data/* dist/data/ 2>/dev/null || true
cd "$REPO"

# The measurement harness and the provider, served from the app's own origin so the page can load
# them without a cross-origin fetch.
cp scripts/landing_audit.js ui-v2/dist/landing-audit.js
[ -f evidence/phase9/provider-injected.js ] && cp evidence/phase9/provider-injected.js ui-v2/dist/asml-provider.js

python3 - "$REPO/ui-v2/dist/index.html" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
tag = '<script src="/asml-provider.js"></script>'
if tag not in s:
    # BUILD ARTIFACT ONLY. ui-v2/index.html, the source, never carries this, so the shipped product
    # has no test provider in it and `npm run build` removes it again.
    s = s.replace("<head>", "<head>\n    " + tag, 1)
    open(p, "w", encoding="utf-8", newline="\n").write(s)
    print("provider tag added to dist/index.html (build artifact only)")
else:
    print("provider tag already present")
PY

bash ./scripts/serve-ui.sh < /dev/null > /dev/null 2>&1
sleep 4
CODE=$(curl -s -o /dev/null -m 10 -w '%{http_code}' http://127.0.0.1:4173/)
echo "server: $CODE"
echo "harness: http://127.0.0.1:4173/landing-audit.js -> $(curl -s -o /dev/null -m 10 -w '%{http_code}' http://127.0.0.1:4173/landing-audit.js)"
echo
echo "Now measure in the Browser pane at 1280x720 and 390x844 by evaluating landing-audit.js."
echo "Results are appended to $OUT."
