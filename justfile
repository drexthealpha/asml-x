# ASML-X command surface. Every recipe here is a command that already appears in an evidence
# file, so this justfile is a shortcut to reproducible work rather than a second, drifting
# description of how to build.

_default:
    @just --list

# Rust workspace
test:
    cargo test --workspace

lint:
    cargo clippy --workspace --all-targets -- -D warnings

# Contracts
forge-test:
    cd contracts && forge test -vv

# Formal verification, both engines. Independent by design: same invariant, two solvers.
halmos:
    cd contracts && halmos --function check_

hevm:
    bash scripts/47d-hevm-argotorg.sh

# Mutation testing. Non-zero exit means mutants SURVIVED, which is a finding, not a crash.
mutants:
    bash scripts/59-cargo-mutants.sh

# Evidence
evidence-check:
    bash scripts/59-tool-ledger-check.sh

graph query:
    bash scripts/60-graph-query.sh "{{query}}"
