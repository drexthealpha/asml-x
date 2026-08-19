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
# THE WORKING TREE, not HEAD. An earlier version archived HEAD, so it tested the last commit and
# reported PASS on config that was already fixed in the working tree, or FAIL on a fix not yet
# committed. The point of this gate is to check what is ABOUT to be pushed.
#
# Tracked files only: no node_modules, no dist, no git history, which is what Vercel receives.
git -C "$REPO" ls-files -z | while IFS= read -r -d "" f; do
  mkdir -p "$WORK/$(dirname "$f")"
  cp "$REPO/$f" "$WORK/$f" 2>/dev/null || true
done
# Untracked-but-staged additions matter too, since they will be in the push.
git -C "$REPO" diff --cached --name-only --diff-filter=A 2>/dev/null | while IFS= read -r f; do
  [ -f "$REPO/$f" ] && mkdir -p "$WORK/$(dirname "$f")" && cp "$REPO/$f" "$WORK/$f"
done
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
# PRETEND AN OLD PNPM IS ALREADY ON THE PATH, which is the condition on Vercel that the first two
# dry runs missed. The image ships its own pnpm, so a build command that says "pnpm" gets THEIRS,
# not the one the install step fetched. Shadowing the name here reproduces that exactly: a run
# that passes now passes because the version is pinned to the binary, not to the PATH.
SHADOW="$WORK/.shadow"
mkdir -p "$SHADOW"
printf '#!/bin/sh
echo "WRONG PNPM: this is the image pnpm, not the pinned one" >&2
exit 1
' > "$SHADOW/pnpm"
chmod +x "$SHADOW/pnpm"
export PATH="$SHADOW:$PATH"
echo "  shadowed `pnpm` so only an explicitly pinned binary can succeed"

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
