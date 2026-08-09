#!/usr/bin/env bash
# Run every job in .github/workflows/ci.yml locally, in the same order, so a push cannot
# be the first time CI is exercised.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="$HOME/.cargo/bin:$HOME/.foundry/bin:$PATH"
cd "$REPO"

PASS=0; FAIL=0
step() {
  printf '%-46s ' "$1"
  # Each step runs in a SUBSHELL. The first version used a bare eval, so the `cd contracts`
  # in one step leaked into every later step and eight checks failed against the wrong
  # working directory. A harness that reports false failures is worse than no harness.
  if ( cd "$REPO" && eval "$2" ) > /tmp/ci_step.log 2>&1; then
    echo "PASS"; PASS=$((PASS+1))
  else
    echo "FAIL"; FAIL=$((FAIL+1))
    tail -12 /tmp/ci_step.log | sed 's/^/    /'
  fi
}

echo "=== job: rust ==="
step "cargo fmt --check" "cargo fmt --all -- --check"
step "clippy -D warnings" "cargo clippy --workspace --all-targets -- -D warnings -A clippy::identity_op"
step "cargo test --workspace" "cargo test --workspace"
step "cargo build --release" "cargo build --release --workspace"

echo
echo "=== job: contracts ==="
step "forge build" "cd contracts && forge build"
step "forge test" "cd contracts && forge test"
step "forge-std present" "test -d contracts/lib/forge-std"
step "suite not vacuous (>= 40 tests)" 'cd contracts && C=$(forge test 2>&1 | grep -oE "[0-9]+ tests passed" | tail -1 | awk "{print \$1}"); test "${C:-0}" -ge 40'

echo
echo "=== job: python ==="
step "py_compile external agent" "python3 -m py_compile agents/external_agent.py"

echo
echo "=== job: secrets ==="
step "no key material tracked" 'test -z "$(git ls-files | grep -iE "keystore|\.env$|\.pass$|id_rsa|secret" | grep -v "\.example$")"'
# The 64-hex grep was removed: it flagged vendored fixtures, public keccak market ids and
# zero-padded batch ids. CI runs gitleaks instead, which cannot be checked locally without
# installing it, so the local guard is the one that matters here: the keystore and .env
# must never be tracked, because that is where real key material actually lives.
step "keystore lives outside the repo" 'test ! -e "$REPO/.asml-keys" && test -f "$HOME/.asml-keys/asml-deployer"'
step ".env not tracked, .env.example is" 'test -z "$(git ls-files | grep -x ".env")"'

echo
echo "=== extras not in CI ==="
step "workflow yaml parses" "python3 -c 'import yaml;yaml.safe_load(open(\".github/workflows/ci.yml\"))'"
step "LICENSE exists" "test -f LICENSE"
step "docs audit clean" 'bash scripts/36-docs-audit.sh >/dev/null 2>&1 && grep -q "0 mismatches" evidence/docs-audit.md'

echo
echo "PASS $PASS   FAIL $FAIL"
if [ "$FAIL" != "0" ]; then
  echo "CI WOULD FAIL. Fix before pushing."
  exit 1
fi
echo "CI would pass."
