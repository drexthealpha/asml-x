#!/usr/bin/env bash
# Tasks 2.2.2 - 2.2.4: build and test the contracts.
# forge-std is fetched as a TARBALL, not with `forge install`, because
# `forge install` creates a git submodule and a commit, which R18 forbids.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO/contracts"

if [ ! -f lib/forge-std/src/Test.sol ]; then
  echo "=== fetching forge-std (tarball, no git) ==="
  mkdir -p lib
  curl -sSL --max-time 180 -o "$HOME/forge-std.tar.gz" \
    https://github.com/foundry-rs/forge-std/archive/refs/heads/master.tar.gz
  rm -rf lib/forge-std
  mkdir -p lib/forge-std
  tar -xzf "$HOME/forge-std.tar.gz" -C lib/forge-std --strip-components=1
  rm -f "$HOME/forge-std.tar.gz"
fi
echo "forge-std present: $(test -f lib/forge-std/src/Test.sol && echo yes || echo NO)"

# forge-std needs ds-test at its remapped path.
if [ ! -f lib/forge-std/lib/ds-test/src/test.sol ]; then
  echo "=== fetching ds-test ==="
  mkdir -p lib/forge-std/lib/ds-test
  curl -sSL --max-time 120 -o "$HOME/ds-test.tar.gz" \
    https://github.com/dapphub/ds-test/archive/refs/heads/master.tar.gz
  tar -xzf "$HOME/ds-test.tar.gz" -C lib/forge-std/lib/ds-test --strip-components=1
  rm -f "$HOME/ds-test.tar.gz"
fi

echo
echo "=== build ==="
forge build 2>&1 | tail -30

echo
echo "=== test ==="
forge test -vv 2>&1 | tail -60
