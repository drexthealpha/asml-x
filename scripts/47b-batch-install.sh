#!/usr/bin/env bash
# Tasks 1.5, 1.7, 1.10, 1.14, 1.16 install half. The tools with unambiguous install paths
# (npm, pip, cargo) go in one batch so the slow compiles overlap.
#
# THINKING: #33 pareto (batch the easy installs, spend the thinking budget on kontrol/hevm),
# #41 algorithmic (one repeatable driver), #22 inversion (record failures, do not skip).
#
# Each tool's SMOKE TEST lives in its own script so 1.19 can delete an evidence file and
# regenerate it. This script only installs.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/batch-install.txt"
mkdir -p "$(dirname "$OUT")"

{
echo "Batch install, tasks 1.5 / 1.7 / 1.10 / 1.14 / 1.16"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

echo "## rust toolchain sanity (1.1 follow-up after the lib.sh PATH fix)"
echo "  rustc: $(rustc --version 2>&1 | head -1)"
echo "  cargo: $(cargo --version 2>&1 | head -1)"
echo

echo "## cargo-mutants (1.7)"
if command -v cargo-mutants >/dev/null 2>&1; then
  echo "  already present: $(cargo mutants --version 2>&1 | head -1)"
else
  cargo install cargo-mutants --locked 2>&1 | tail -4
  echo "  installed: $(cargo mutants --version 2>&1 | head -1)"
fi
echo

echo "## scribble (1.5), npm global"
if command -v scribble >/dev/null 2>&1; then
  echo "  already present: $(scribble --version 2>&1 | head -1)"
else
  npm install -g eth-scribble 2>&1 | tail -4
  echo "  scribble: $(scribble --version 2>&1 | head -1 || echo NOT ON PATH)"
fi
echo

echo "## python tools in one venv (1.10 paperscraper, 1.14 river)"
VENV="$HOME/.asml-venv"
if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV" 2>&1 | tail -2
fi
"$VENV/bin/pip" install --quiet --upgrade pip 2>&1 | tail -1
echo "  installing paperscraper and river (this takes a few minutes)"
"$VENV/bin/pip" install --quiet paperscraper river 2>&1 | tail -6
echo "  paperscraper: $("$VENV/bin/python" -c 'import paperscraper; print(paperscraper.__version__ if hasattr(paperscraper,"__version__") else "installed")' 2>&1 | head -1)"
echo "  river:        $("$VENV/bin/python" -c 'import river; print(river.__version__)' 2>&1 | head -1)"
echo

echo "## just and insta (1.16)"
if command -v just >/dev/null 2>&1; then
  echo "  just already present: $(just --version 2>&1)"
else
  cargo install just --locked 2>&1 | tail -3
  echo "  just: $(just --version 2>&1 | head -1)"
fi
echo "  insta is a dev-dependency, added to Cargo.toml in the 1.16 smoke test"
echo

echo "## duckdb python (1.16, used by 8.6)"
"$VENV/bin/pip" install --quiet duckdb 2>&1 | tail -3
echo "  duckdb: $("$VENV/bin/python" -c 'import duckdb; print(duckdb.__version__)' 2>&1 | head -1)"
echo
echo "venv path for later scripts: $VENV"
} 2>&1 | tee "$OUT"

echo
echo "written: $OUT"
