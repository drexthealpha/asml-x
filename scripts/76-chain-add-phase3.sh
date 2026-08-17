#!/usr/bin/env bash
# Phase 3 chain-of-evidence rows. A script file, not an inline command, because E4: the wsl arg
# layer stripped the helper variable and turned "$A C-300 ..." into "C-300: command not found".
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

add() { bash "$REPO/scripts/43-chain-add.sh" "$@"; }

add C-300 \
  "HypeTerminal cloned at pinned commit a61992ed and mapped: 517 files and 70389 lines in apps/terminal, with per-file line counts so the study can cite file:line" \
  "evidence/hypeterminal/file-tree.txt" "bash scripts/73-clone-hypeterminal.sh" DEMONSTRATED 3.1

add C-301 \
  "The UI study carries 70 path:line citations across 20 files, zero invalid, checked by a script that fails on any citation pointing past the end of a file" \
  "evidence/ui-study.md, evidence/hypeterminal/citation-audit.txt" \
  "bash scripts/74-verify-ui-study.sh" DEMONSTRATED 3.7

add C-302 \
  "The frontend primitive decision is recorded with what transfers from HypeTerminal and what does not, each with a reason" \
  "docs/decisions/ADR-013-ui-primitives.md" "bash scripts/74-verify-ui-study.sh" DEMONSTRATED 3.6

echo "rows now: $(grep -c '^| C-' "$REPO/evidence/CHAIN-OF-EVIDENCE.md")"
