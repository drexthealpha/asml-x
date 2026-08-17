#!/usr/bin/env bash
# Batch install, corrected. Fixes two identified failures from 47b rather than retrying it.
#
# THINKING: #7 counterfactual (each failure had one identifiable cause; find it, do not
# re-run and hope), #16 lateral (uv is already installed and manages its own Python, so stop
# fighting apt for python3-venv), #50 empirical (verify every tool produces output).
#
# FAILURE 1: `npm install -g eth-scribble` exited -13, which is EACCES. The package name was
#   correct (verified: npmjs.com/package/eth-scribble). Global installs need a writable
#   prefix, so set a user-level prefix instead of sudo.
# FAILURE 2: `python3 -m venv` created nothing. Ubuntu 22.04 ships python3 without the venv
#   module unless python3.10-venv is installed. uv is ALREADY installed from task 1.2 and
#   brings its own interpreter, so use `uv venv`.
#
# E4: no $HOME anywhere. The wsl arg layer strips it. Literal /home/zulab throughout.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="/home/zulab/.cargo/bin:/home/zulab/.local/bin:/home/zulab/.npm-global/bin:$PATH"

OUT="$REPO/evidence/phase0/batch-install.txt"
mkdir -p "$(dirname "$OUT")"
VENV="/home/zulab/.asml-venv"

{
echo "Batch install (corrected), tasks 1.5 / 1.7 / 1.10 / 1.14 / 1.16"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

echo "## Already confirmed installed"
echo "  rustc:         $(rustc --version 2>&1 | head -1)"
echo "  cargo:         $(cargo --version 2>&1 | head -1)"
echo "  cargo-mutants: $(cargo mutants --version 2>&1 | head -1)"
echo "  just:          $(just --version 2>&1 | head -1)"
echo "  uv:            $(uv --version 2>&1 | head -1)"
echo "  halmos:        $(halmos --version 2>&1 | head -1)"
echo "  hevm:          $(hevm version 2>&1 | head -1)"
echo "  z3:            $(z3 --version 2>&1 | head -1)"
echo "  gitleaks:      $(gitleaks version 2>&1 | head -1)"
echo

echo "## FIX 1: scribble via a user-writable npm prefix (was EACCES, exit -13)"
npm config set prefix /home/zulab/.npm-global 2>&1 | tail -1
mkdir -p /home/zulab/.npm-global
if command -v scribble >/dev/null 2>&1; then
  echo "  already present: $(scribble --version 2>&1 | head -1)"
else
  npm install -g eth-scribble 2>&1 | tail -4
  echo "  scribble: $(scribble --version 2>&1 | head -1 || echo 'STILL NOT ON PATH')"
fi
echo

echo "## FIX 2: venv via uv (python3 -m venv produced nothing, venv module absent)"
# FIX 3: the venv must be on 3.12, not the system 3.10.
#
# `uv venv --python 3.12` silently fell back to the system 3.10 because no 3.12 interpreter
# was present. river 0.23.0 then had no 3.10 wheel for this platform, tried to build from
# source, and failed. Fetch a real 3.12 first so wheels resolve instead of compiling.
uv python install 3.12 2>&1 | tail -2
PY312=$(uv python find 3.12 2>/dev/null)
echo "  uv python 3.12 at: ${PY312:-NOT FOUND}"
if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" --version 2>&1 | grep -q '3\.12'; then
  rm -rf "$VENV"
  uv venv "$VENV" --python 3.12 2>&1 | tail -3
fi
echo "  venv python: $("$VENV/bin/python" --version 2>&1 | head -1 || echo ABSENT)"
echo

echo "## paperscraper (1.10), river (1.14), duckdb (1.16) into that venv"
if [ -x "$VENV/bin/python" ]; then
  VIRTUAL_ENV="$VENV" uv pip install --python "$VENV/bin/python" \
    paperscraper river duckdb 2>&1 | tail -8
  echo
  echo "  paperscraper: $("$VENV/bin/python" -c 'import paperscraper,sys; print("import OK")' 2>&1 | tail -1)"
  echo "  river:        $("$VENV/bin/python" -c 'import river; print(river.__version__)' 2>&1 | tail -1)"
  echo "  duckdb:       $("$VENV/bin/python" -c 'import duckdb; print(duckdb.__version__)' 2>&1 | tail -1)"
else
  echo "  venv unavailable, cannot install python tools"
fi

echo
echo "venv for later scripts: $VENV"
} 2>&1 | tee "$OUT"

echo
echo "written: $OUT"
