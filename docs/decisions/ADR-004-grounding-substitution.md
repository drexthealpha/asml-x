# ADR-004: gemini-grounding substituted

Date 9 Aug 2026. Status ACCEPTED.

## Context
R14 requires a freshness check through gemini-grounding before confirming against
a primary source.

## What happened
One test query to the native generateContent endpoint with the google_search tool
returned a transport failure: SSL_read unexpected eof from
generativelanguage.googleapis.com. Same interference pattern as this machine's
okx.com DNS block. Per instruction and R17, not investigated.

## Decision
R14's freshness step is WebSearch plus the DoH-pinned direct fetch implemented in
scripts/lib.sh. That combination produced every verified finding so far, including
the chain ID 1952 correction and the OP Stack determination.

## Honesty note
Recorded as "unreachable from this network", NOT as "no free quota". The quota
question was never answered, and claiming otherwise would be an unevidenced claim.
