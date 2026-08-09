# ADR-008: hand-rolled JSON-RPC reads, cast for signing

Date 9 Aug 2026. Status ACCEPTED.

## Decision
The runtime talks to chain 1952 over JSON-RPC with a small hand-written client
(ureq plus about eighty lines of static ABI coding). Transaction SIGNING is
delegated to  as a subprocess against the encrypted keystore.

## Why not alloy or ethers for reads
The runtime needs five static read shapes and no dynamic ABI types at all. Encoding
those by hand is unambiguous and testable against known selectors, which the tests
do. The dependency tree of a full SDK would dominate build time for the whole
workspace. keccak256 is NOT hand-rolled: tiny-keccak is used, because a subtly wrong
hash produces wrong selectors and failures that look like contract bugs.

If dynamic ABI types are ever needed, REPLACE this module with alloy-sol-types
rather than extending it. Hand-rolled dynamic encoding is where the real bugs live.

## Why cast for signing
A hand-rolled secp256k1 signer and RLP encoder is exactly the brittle plumbing R9
forbids hiding behind a clean interface.  already produced every verified
transaction in this project, holds the keystore, and is battle-tested. The runtime
decides and constructs the batch; cast signs and submits.

## Cost, stated plainly
A subprocess per submission costs tens of milliseconds and would be wrong for a
latency-sensitive production system. At this cadence it is irrelevant. It is
disclosed in the README rather than described as a native signer.
