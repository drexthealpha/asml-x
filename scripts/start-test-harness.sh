#!/usr/bin/env bash
# Build the UI and start the Phase 9 verification harness: the static server and the TEST-ONLY signer.
#
# The signer exists because task 9.0 (install a browser extension) is USER HANDLES and outstanding,
# and tasks 9.3 and 9.4 need the UI to cause a REAL transaction. It shells out to `cast`, so the key
# never enters the browser and ADR-008's decision that signing lives in cast is preserved. It is
# never referenced by ui-v2 source and only ever exists in `dist`, which `npm run build` regenerates
# without it.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

cd "$REPO/ui-v2"
npm run build 2>&1 | tail -3
mkdir -p dist/data
cp -r public/data/* dist/data/ 2>/dev/null || true
cd "$REPO"

cp scripts/landing_audit.js ui-v2/dist/landing-audit.js
cp evidence/phase9/provider-injected.js ui-v2/dist/asml-provider.js 2>/dev/null || true

python3 - "$REPO/ui-v2/dist/index.html" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
tag = '<script src="/asml-provider.js"></script>'
if tag not in s:
    s = s.replace("<head>", "<head>\n    " + tag, 1)
    open(p, "w", encoding="utf-8", newline="\n").write(s)
    print("provider tag added to dist/index.html (BUILD ARTIFACT ONLY)")
else:
    print("provider tag already present")
PY

# E13: pkill -x, never pkill -f, or this kills its own invoking shell.
pkill -x python3 2>/dev/null || true
sleep 1

bash ./scripts/serve-ui.sh < /dev/null > /dev/null 2>&1
sleep 3

# E12: setsid plus nohup, or the signer dies when this invocation exits.
REPO="$REPO" RPC="$XLAYER_TESTNET_RPC" KEYFILE="$KEYFILE" KEYPASS="$(keystore_pass)" \
  setsid nohup python3 "$REPO/scripts/test_signer.py" > /home/zulab/test-signer.log 2>&1 < /dev/null &
sleep 3

echo "ui:     $(curl -s -o /dev/null -m 10 -w '%{http_code}' http://127.0.0.1:4173/)"
echo "signer: $(curl -s -o /dev/null -m 10 -w '%{http_code}' -X POST -H 'content-type: application/json' -d '{"to":"0x0"}' http://127.0.0.1:4177/)  (403 expected: destination not allowlisted)"
head -2 /home/zulab/test-signer.log
