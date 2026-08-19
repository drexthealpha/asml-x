#!/usr/bin/env bash
# Deploy ASML-X to Vercel: static app plus the serverless functions that sign OKX requests.
#
# WHY SERVERLESS FUNCTIONS AND NOT A STATIC BUILD. The feeds need an HMAC signature, which needs
# the API secret. A static deployment would either ship the secret to the browser (never) or serve
# the JSON files baked in at build time, which would be frozen at the moment of the build and would
# look exactly like the hardcoded data this project has spent days removing.
#
# The functions in ui-v2/api do the same signing the local Python feed server does, from Vercel's
# environment. The browser sees results only.
#
# WHAT MUST BE SET IN THE VERCEL PROJECT before the feeds work:
#   OKX_API_KEY  OKX_SECRET  OKX_PASSPHRASE
# Optional: OKX_PROJECT, ASML_X402_PRICE (turns the paid quote endpoint on).
#
# WITHOUT THEM the app still deploys, /api/rwastate still works (it reads the public chain), and
# the price feeds return a 503 that names the missing variables. It degrades honestly rather than
# rendering empty.
#
# EVIDENCE PATH: evidence/phase20/vercel.txt
set -uo pipefail
cd "$(dirname "$0")/../ui-v2"

OUT="../evidence/phase20/vercel.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

echo "=== preflight ==="
if ! command -v vercel >/dev/null 2>&1; then
  echo "installing the Vercel CLI"
  npm install -g vercel@48.4.0 2>&1 | tail -2
fi
vercel --version

echo
echo "=== the app builds before anything is deployed ==="
pnpm build 2>&1 | grep -E "error|built" | tail -3

echo
echo "=== functions present ==="
ls api/*.js | sed 's|^|  |'

echo
echo "=== deploy ==="
echo "This needs a logged-in Vercel account. If it stops at a prompt, run:"
echo "    cd ui-v2 && vercel login"
echo "then re-run this script."
echo
vercel deploy --prod --yes 2>&1 | tail -20
