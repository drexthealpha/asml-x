#!/usr/bin/env bash
# Thin wrapper for the official `onchainos` CLI.
#
# WHY A WRAPPER. CLAUDE.md E4: exporting PATH through `wsl -- bash -c` interpolates the Windows PATH,
# which contains "Program Files (x86)", and the unquoted parentheses are a shell syntax error before
# anything runs. Every onchainos call goes through this file so that cannot happen again.
#
# Credentials are read from ~/.asml-keys/okx.env, which is OUTSIDE the repo and gitignored.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

# The CLI reads its API-key credentials from the environment. Sourcing here means no key is ever
# typed on a command line, where it would land in shell history and process listings.
if [ -f "$HOME/.asml-keys/okx.env" ]; then
  set -a
  . "$HOME/.asml-keys/okx.env"
  set +a
fi

# NAME MAPPING, and this was the whole blocker. The CLI resolves its credentials from
# OKX_API_KEY / OKX_SECRET_KEY / OKX_PASSPHRASE (cli/src/client.rs:345-372). This project's env
# file predates the CLI and uses OKX_SECRET / OKX_PROJECT. Without the mapping the CLI silently
# falls back to AuthMode::Anonymous: it does not error, it just runs unauthenticated and returns
# thin or empty data, which looks like the API having nothing to say rather than a missing key.
#
# Only set what is absent, so an explicitly exported value always wins.
export OKX_API_KEY="${OKX_API_KEY:-${OKX_ACCESS_KEY:-}}"
export OKX_SECRET_KEY="${OKX_SECRET_KEY:-${OKX_SECRET:-}}"
export OKX_PASSPHRASE="${OKX_PASSPHRASE:-}"

exec onchainos "$@"
