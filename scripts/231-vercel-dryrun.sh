#!/usr/bin/env bash
# Run Vercel's EXACT build in a clean clone, before pushing.
#
# WHY A CLEAN CLONE AND NOT THE WORKING TREE. The working tree has node_modules already populated,
# so `pnpm install --frozen-lockfile` there can succeed against a lockfile Vercel would reject.
# That is precisely the failure that just happened: the build passed locally seven times and died
# on Vercel with "Ignoring not compatible lockfile", because the pinned pnpm was not the version
# that wrote the lockfile.
#
# This clones the repo into a temporary directory and runs the same three commands Vercel runs, in
# the same order, with nothing cached. If it passes here it passes there.
#
# EVIDENCE PATH: evidence/phase20/vercel-dryrun.txt
set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

OUT="$REPO/evidence/phase20/vercel-dryrun.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

WORK="$HOME/asml-vercel-dryrun"
rm -rf "$WORK"
mkdir -p "$WORK"

echo "=== cloning the working tree as Vercel would clone the repo ==="
# Files only, no node_modules, no dist, no git history. `git archive` gives exactly the tracked
# content, which is what Vercel receives.
git -C "$REPO" archive --format=tar HEAD 2>/dev/null | tar -x -C "$WORK" || {
  echo "no commit yet; copying the tracked file list instead"
  git -C "$REPO" ls-files -z | tar --null -T - -cf - | tar -x -C "$WORK"
}
echo "  files: $(find "$WORK" -type f | wc -l)"

echo
echo "=== the config Vercel will read ==="
PM=$(python3 -c "import json;print(json.load(open('$WORK/package.json')).get('packageManager','(none)'))" 2>/dev/null)
IC=$(python3 -c "import json;print(json.load(open('$WORK/vercel.json'))['installCommand'])" 2>/dev/null)
BC=$(python3 -c "import json;print(json.load(open('$WORK/vercel.json'))['buildCommand'])" 2>/dev/null)
LV=$(head -1 "$WORK/ui-v2/pnpm-lock.yaml" 2>/dev/null)
echo "  packageManager   $PM"
echo "  installCommand   $IC"
echo "  buildCommand     $BC"
echo "  lockfile         $LV"

echo
echo "=== 1. install command ==="
cd "$WORK"
eval "$IC" 2>&1 | tail -3
echo "  pnpm now: $(pnpm --version 2>/dev/null || echo missing)"

echo
echo "=== 2. build command, frozen lockfile, no cache ==="
if eval "$BC" 2>&1 | tail -14; then
  echo
  echo "GATE: PASS  Vercel's exact build succeeds from a clean tree"
else
  echo
  echo "GATE: FAIL  this is what Vercel would show"
  exit 1
fi

echo
echo "=== 3. the output directory Vercel will serve ==="
ls "$WORK/ui-v2/dist" 2>/dev/null | head -6
echo "  functions:"
ls "$WORK/api"/*.js 2>/dev/null | sed 's|.*/|    |'
