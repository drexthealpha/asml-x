#!/usr/bin/env bash
# Which node and which pnpm is actually running? The 1.15 build failed with tsc unable to
# resolve react-dom/client despite 92 packages installed and NO pnpm-lock.yaml written, and
# `ps` showed the running tsc as
#   node /mnt/c/Users/zulab/AppData/Roaming/npm/node_modules/typescript/bin/tsc -b
# which is the WINDOWS npm global install. That is the suspect: a Windows node resolving
# /mnt/c/... as if it were a Windows path, or a Windows toolchain walking a Linux-side
# node_modules tree of symlinks. Establish the fact before changing anything.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
echo "node:  $(command -v node)"
echo "  version: $(node --version 2>&1)"
echo "  is it a Windows exe reached over interop?"
file "$(command -v node)" 2>/dev/null | cut -c1-160
echo "npm:   $(command -v npm)"
echo "pnpm:  $(command -v pnpm)"
echo "  version: $(pnpm --version 2>&1 | tail -1)"
echo
echo "apt/nodesource Linux node present?"
ls -la /usr/bin/node /usr/local/bin/node /home/zulab/.nvm 2>&1 | head -6
echo
echo "ui-v2 node_modules shape:"
ls -la /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/ui-v2/node_modules 2>/dev/null | head -8
echo "  .bin contents:"
ls /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/ui-v2/node_modules/.bin 2>/dev/null | head -12
echo "  react-dom present as a real dir?"
ls -la /mnt/c/Users/zulab/OneDrive/Desktop/ASML-X/ui-v2/node_modules/react-dom 2>&1 | head -4
