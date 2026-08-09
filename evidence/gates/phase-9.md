# Phase 9 gate: judge-facing documentation

Captured 9 Aug 2026.

## Written

| document | purpose |
|---|---|
| [README.md](../../README.md) | What it is, what is real and what is not, architecture, the three decisions that matter, verification table, deployed addresses, measured numbers, ten-minute run |
| [JUDGE-GUIDE.md](../../JUDGE-GUIDE.md) | Five-minute path in order, each step naming what would falsify the claim, ending with "the fastest way to attack this submission" |
| [docs/limitations.md](../../docs/limitations.md) | Every known weakness, each fixed, cut, or stated with a reason |
| [docs/invariants.md](../../docs/invariants.md) | All 14 symbolic theorems, plus what is enforced by types, verified live, and explicitly NOT proven |
| [docs/mainnet-path.md](../../docs/mainnet-path.md) | Forward commitment with dates, and the Launch Grant arithmetic |
| [docs/decisions/ADR-010](../../docs/decisions/ADR-010-coordination-auth.md) | API-key auth rather than wallet signatures |

## The docs audit, and what it caught

`scripts/36-docs-audit.sh` checks the documents against the repository rather than trusting
them. It verifies test counts against actual runs, mutation tables for gaps and inapplicable
patterns, that every deployed address in `deployments.json` appears in the README, that every
file a document links to exists, and that no judge-facing document contains an em dash.

**Final result: 0 mismatches** ([evidence/docs-audit.md](../docs-audit.md)).

It found two real unbacked claims on its first useful run:

1. **The docs claimed 49 Foundry tests when there were 50.** The crossed-book tests added in
   Phase 8 were never counted. Corrected across README, RESUME and the phase-8 gate.
2. **README linked `docs/invariants.md`, which did not exist.** It had been planned in Phase 3
   and never written. Now written, and it is one of the more useful documents in the repo
   because it separates the 14 proven properties from the five explicitly unproven ones.

It also produced ten false mismatches on its very first run, caused by a bug in the audit
itself: `grep -c` prints `0` and *also* exits non-zero, so `|| echo 0` appended a second zero
and every comparison against `"0"` failed. Worth recording, because an audit that reports
false failures gets ignored, which is worse than no audit.

## Notable content decisions

- The README leads with **what is not real**, before the architecture. Exchange OS has no
  testnet surface and the venue and RWA instrument are self-deployed, so a judge learns that
  from us in the first screen rather than discovering it later.
- The judge guide ends with a section titled "the fastest way to attack this submission",
  listing the four strongest attacks and where each is already documented. A weakness a judge
  finds unaided reads as concealment; the same weakness volunteered reads as engineering
  judgement.
- `docs/invariants.md` has a "Stated but NOT proven" table. The most valuable entry in it is
  that no proof relates the offchain risk engine to the onchain guard. They implement the
  same refusals deliberately and agreed in every observed case, but that agreement is not
  proven, and it is the highest-value future proof in the project.
- `docs/mainnet-path.md` states plainly that **the Launch Grant is not reachable** for this
  project. API-executed volume is excluded and the cutoff is 31 Aug, ten days after
  submission, so an autonomous agent trading through an API cannot generate qualifying
  volume. Claiming otherwise would be arithmetic nobody should believe.

## Remaining Phase 9 items, blocked on the user or not yet done

- **Public GitHub repo.** The user creates it and performs all commits and pushes (R18). The
  repo must be public before the clone-and-run check and before a judge can read it.
- **Project X account.** The user is creating it. The submission post must mention
  @XLayerOfficial and its URL is a required form field.
- **Public UI deployment.** The dashboard is a single static file plus three JSON reads, so
  Vercel or Cloudflare Pages hosts it as-is. Not done.
- **Demo video, 3 minutes.** Not recorded. Must show a real explorer page with a real tx, the
  risk engine refusing an action, and the external Python agent in its own terminal, and must
  state on screen whether the run is continuous or edited.
- **Clean-container clone-and-run.** Cannot be done until the repo is public.
