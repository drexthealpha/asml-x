#!/usr/bin/env bash
# RouterExecutor test suite. Script file per CLAUDE.md E4: the Windows PATH contains
# "Program Files (x86)", and exporting it through `wsl -- bash -c` puts unquoted parentheses on the
# command line, which is a shell syntax error before anything runs.
set -uo pipefail
cd "$(dirname "$0")/../contracts"
export PATH="$HOME/.foundry/bin:$PATH"
forge test --match-contract RouterExecutorTest -vv
