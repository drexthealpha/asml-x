#!/usr/bin/env bash
# Common environment for every ASML-X script. Source this first.
# Exists because passing $vars or $(...) through `wsl -- bash -c` from the agent
# shell strips them (ENVIRONMENT FACT E4). All real work goes in script files.

# ~/.cargo/bin was missing here until task 1.1, which made rustc and cargo report as
# MISSING in any script that relied on lib.sh for PATH.
export PATH="$HOME/.cargo/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"

# EVERY VALUE BELOW IS OVERRIDABLE FROM THE ENVIRONMENT, defaulting to the real testnet.
#
# This used to hardcode all of them, which meant the deploy, trade and settle gates could only ever
# run against live X Layer with the one funded keystore on one machine. CI could therefore not run
# them at all, and "skip the gates that need a key" is not an answer: it reports green over a
# smaller set than the reader assumes.
#
# With overrides, the SAME scripts run unchanged against a local `anvil` chain with a throwaway
# funded account. No real key ever reaches CI, and the gates still deploy real contracts, submit
# real transactions and settle real trades against a real EVM.
#
# Verified 9 Aug 2026 by scripts/probe-rpc.sh
export XLAYER_TESTNET_RPC="${XLAYER_TESTNET_RPC:-https://testrpc.xlayer.tech}"
export XLAYER_TESTNET_RPC_FALLBACK="${XLAYER_TESTNET_RPC_FALLBACK:-https://xlayer-testnet.drpc.org}"
export XLAYER_TESTNET_CHAIN_ID="${XLAYER_TESTNET_CHAIN_ID:-1952}"
export XLAYER_MAINNET_RPC="${XLAYER_MAINNET_RPC:-https://rpc.xlayer.tech}"
export XLAYER_MAINNET_CHAIN_ID="${XLAYER_MAINNET_CHAIN_ID:-196}"

export DEPLOYER_ADDRESS="${DEPLOYER_ADDRESS:-0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46}"
export KEYDIR="${KEYDIR:-$HOME/.asml-keys}"
export KEYFILE="${KEYFILE:-$KEYDIR/asml-deployer}"
export PASSFILE="${PASSFILE:-$KEYDIR/keystore.pass}"

# DERIVED FROM THIS FILE'S OWN LOCATION, not hardcoded.
#
# This used to be `export REPO="/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"`, an absolute path on one
# developer's Windows machine. Every script here sources this file, so every gate in the project was
# pointed at a directory that exists nowhere else.
#
# That contradicted the project's central claim. The evidence chain says each claim "reproduces from
# a clean clone", and a clean clone anywhere but that one machine could not run a single script. CI
# is what surfaced it: the first pipeline run would have failed every job for this one line.
#
# `${BASH_SOURCE[0]}` is this file regardless of which script sourced it or from where, so `..` is
# the repo root whether the clone lives in a home directory, a GitHub runner, or a Windows mount.
# It also removes the developer's username from the one file every other script reads.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO

# Credentials live in ~/.profile. `bash -lc` does not reliably source dotfiles
# (E2, do not debug), so read them out of the file directly when absent.
load_cred() {
  local name="$1"
  if [ -z "${!name:-}" ] && [ -f "$HOME/.profile" ]; then
    local val
    val=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${name}=" "$HOME/.profile" \
          | tail -1 | sed -E 's/^[^=]*=//' | tr -d "\"'" | tr -d '\r')
    export "$name=$val"
  fi
}

load_all_creds() {
  load_cred GEMINI_API_KEY
  load_cred GITHUB_TOKEN
  load_cred KAGGLE_USERNAME
  load_cred KAGGLE_KEY
}

# Prints presence only, never values.
cred_status() {
  for n in GEMINI_API_KEY GITHUB_TOKEN KAGGLE_USERNAME KAGGLE_KEY; do
    local v="${!n:-}"
    if [ -n "$v" ]; then
      printf '%-18s PRESENT (len %s)\n' "$n" "${#v}"
    else
      printf '%-18s MISSING\n' "$n"
    fi
  done
}

keystore_pass() { cat "$PASSFILE"; }
