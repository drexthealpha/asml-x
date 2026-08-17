# Phase 2 gate: chain-of-evidence backfill

This is the phase that makes the submission auditable. The v1 build had scattered evidence and an
index file with a header, a scope note and **zero rows**, which means R-EVIDENCE ("a claim with no
evidence path is DELETED") would have deleted the README.

`evidence/CHAIN-OF-EVIDENCE.md` now holds **33 rows**, each with a claim, an artifact, an exact
reproduce command, a DEMONSTRATED or INFERRED label, and a task number. Every row was added through
`scripts/43-chain-add.sh`, which REFUSES a DEMONSTRATED row whose artifact is not on disk, so a row's
presence means the artifact exists.

## 2.1 Claim inventory

**244 factual assertions extracted from 29 judge-facing documents**, each with a `file:line` origin.
`evidence/phase2/claim-inventory.txt` plus a CSV for machine use.

Three real extraction bugs, all found by running it rather than by reading it:

1. **`JUDGE-GUIDE.md` was scanned as zero lines.** The path in the extractor said `docs/JUDGE-GUIDE.md`
   and the file is at the repo root. A missing target was silently skipped, so the most judge-facing
   document in the repo produced no rows in a clean-looking inventory. Missing targets are now
   REPORTED as findings.
2. **Line-level splitting produced fragments.** Markdown hard-wraps prose, so one row was the bare
   text of a link because its sentence started on the previous line. Fixed by joining paragraphs and
   keeping the line each starts on.
3. **Recall was far too low.** Requiring a digit in the sentence found only 4 assertions in a
   236-line README. A second rule (a claim verb plus a concrete subject) took the total from 122 to
   244. An inventory that misses claims is worse than one that over-includes, because 2.6 deletes
   claims that fail and a claim missing from the inventory is never checked at all.

## 2.2 The graph, not grep

R-SEARCH-4 was in v1's rules and was never once obeyed, because the tool was never installed. Four
inventory questions answered from the code graph with the query recorded verbatim:
`evidence/phase2/graph-query-log.txt`.

The useful one: "which functions read the clock?" ADR-005 claims the risk engine reads no clock and
takes time as an argument. The graph shows `now_ms` inside `risk-engine` is a **Field**
(`crates/risk-engine/src/lib.rs:138`), not a call, while the actual clock reads live in
`coordination-api` and `chain-client`. That is the claim, confirmed structurally.

One honest limit is recorded with it: `search_graph` ranks by BM25 over identifier names, so it finds
what is NAMED for a concept and can miss what implements it under another name. It is a better
starting point than grep and it is not a proof of absence, which is why the clock question alone
carries a second independent check.

## 2.3 Chain and deployment claims, re-derived from chain

`evidence/phase2/chain-id.txt`, `evidence/phase2/deployment-bytecode.txt`.

- chain id **1952**, confirmed live.
- block time **1.000s**, measured as 300 seconds over 300 blocks rather than quoted. The README said
  "~1.0 s, measured twice independently" and now says the measured number.
- **7 of 7** addresses in `docs/verified/deployments.md` return non-empty bytecode, each with a
  keccak of the returned code so a redeploy would show as a changed hash at an unchanged address.
- Addresses are PARSED from the document under test, so a typo or an invented address fails here
  rather than being read past.

## 2.4 Transaction claims, re-derived from chain

`evidence/phase2/tx-receipts.json`, `evidence/phase2/tx-claims.txt`.

**18 transactions resolved, 18 with status 0x1, 0 reverted.** Twelve further 32-byte values are
reported as NOT-A-TX (market ids, keccak hashes), because the difference between "not a transaction"
and "a transaction that does not exist" is the whole point of the task.

Two process notes worth keeping:

- The first run scanned only README, JUDGE-GUIDE, docs/ and gates/, and found **5** candidates. That
  was obviously too few for a build with a live spine run, a first transaction and an RWA session.
  Widening the scope to all of `evidence/` found 39. An undercount here would have produced a PASS
  that covered three transactions while implying it covered all of them.
- Widening pulled in halmos counterexample dumps full of ABI-encoded words. Those are excluded by a
  stated rule (sixteen leading zero bytes cannot be a keccak hash) and the excluded count is printed,
  so the exclusion is auditable rather than silent.

## 2.7 Inline references

README and JUDGE-GUIDE now carry `[C-xxx]` tags that resolve to the index, plus the two commands that
re-derive the onchain facts from chain while ignoring every table in the repo.

Two documentation defects fixed in passing:

1. The README's repository layout listed `CLAUDE.md` and `RESUME.md`, both of which are gitignored. A
   judge reading that line would look for files that are not there.
2. The JUDGE-GUIDE said 40 `OrderNotionalTooLarge` refusals meant "the engine wanted to trade larger
   and was refused". The count is real; the interpretation was wrong, and the correction is now in
   the document with its own detector. See `evidence/phase4/journal-provenance.md`.

## Still open in this phase

- **2.5** re-verify every formal and mutation claim in one run. Script written
  (`scripts/69-reverify-formal-mutation.sh`), not yet executed end to end.
- **2.6** cut anything that does not reproduce. `scripts/44-chain-verify.sh` exists and runs every
  row's command; the cut list is produced from its report.
- **2.8** five-row random red team from a clean checkout.

Stated as open rather than folded into a summary, because a gate report that implies completeness it
does not have is the same defect as a claim without an artifact.
