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

## AMENDMENT, 11 Aug 2026, task 1.11: the quota question is now answered

The "unreachable from this network" finding was WRONG, and the honesty note above is the
reason the error was recoverable: it recorded the limit of what had been established instead
of guessing. What task 1.11 established, by retrying with the transport corrected per E3 and
E9:

- The host IS reachable. DoH resolution plus `curl --resolve` reaches
  generativelanguage.googleapis.com and gets real HTTP responses, not SSL eof.
- The key IS valid. `GET /v1beta/models` returns the full model list, and a retired model name
  returns an authenticated HTTP 404 whose body names the retirement. Never a 401. E3 predicted
  exactly this: a 401 on an AQ. key means the route is wrong, not the key.
- Two model names from memory were both retired. Enumerating the API's own model list is what
  fixed that, rather than guessing a third name.
- The refusal is HTTP **429** on every available model, across three spaced attempts on
  `gemini-flash-latest` with 35 second backoff. That is a rate or quota ceiling.

So the correct record is: gemini-grounding fails on QUOTA, not on network and not on
capability. Evidence: `evidence/phase0/gemini-grounding.txt`. Reproduce:
`bash scripts/57c-gemini-429.sh`.

The DECISION is unchanged: R-SEARCH-2 rung 1 is unavailable, and the ladder is satisfied at
rung 2 (WebSearch), which has carried every verified finding in this build. What changes is
that the reason is now precise. And the constraint it implies is unchanged too: no Gemini
answer is quoted as grounded anywhere in this repo, because no grounded answer was ever
obtained.
