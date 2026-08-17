#!/usr/bin/env bash
# Common environment for every ASML-X script. Source this first.
# Exists because passing $vars or $(...) through `wsl -- bash -c` from the agent
# shell strips them (ENVIRONMENT FACT E4). All real work goes in script files.

# ~/.cargo/bin was missing here until task 1.1, which made rustc and cargo report as
# MISSING in any script that relied on lib.sh for PATH.
export PATH="$HOME/.cargo/bin:$HOME/.foundry/bin:$HOME/.local/bin:$PATH"

# Verified 9 Aug 2026 by scripts/probe-rpc.sh
export XLAYER_TESTNET_RPC="https://testrpc.xlayer.tech"
export XLAYER_TESTNET_RPC_FALLBACK="https://xlayer-testnet.drpc.org"
export XLAYER_TESTNET_CHAIN_ID="1952"
export XLAYER_MAINNET_RPC="https://rpc.xlayer.tech"
export XLAYER_MAINNET_CHAIN_ID="196"

export DEPLOYER_ADDRESS="0x7BdD2d0D1728Df5bEF8FAae8de85c3dD21a5dE46"
export KEYDIR="$HOME/.asml-keys"
export KEYFILE="$KEYDIR/asml-deployer"
export PASSFILE="$KEYDIR/keystore.pass"

export REPO="/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"

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
