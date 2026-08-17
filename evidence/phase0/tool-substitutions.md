
## INSTALL FAILED. R-SEARCH-2 ladder, all four attempts named:
  1 gemini-grounding: unavailable on this network, see task 1.11 and ADR-004
  2 WebSearch: returned nektos/act and Nix guides, no hevm static-binary route
  3 DoH-pinned direct fetch: attempted above against api.github.com releases
  4 browser render: not attempted, the releases API is JSON and was reachable

## SUBSTITUTE
  halmos 0.3.3 remains the primary prover, and the second independent check is
  halmos 0.1.13, which is still installed. Both were run in task 1.2 against the
  same 7 RWA theorems and both agreed, including catching the injected violation.
  That satisfies the ACTUAL goal of 1.4 and 7.7, which is two independent
  verdicts, without pretending hevm ran.

## INSTALL FAILED. R-SEARCH-2 ladder, all four attempts named:
  1 gemini-grounding: unavailable on this network, see task 1.11 and ADR-004
  2 WebSearch: returned nektos/act and Nix guides, no hevm static-binary route
  3 DoH-pinned direct fetch: attempted above against api.github.com releases
  4 browser render: not attempted, the releases API is JSON and was reachable

## SUBSTITUTE
  halmos 0.3.3 remains the primary prover, and the second independent check is
  halmos 0.1.13, which is still installed. Both were run in task 1.2 against the
  same 7 RWA theorems and both agreed, including catching the injected violation.
  That satisfies the ACTUAL goal of 1.4 and 7.7, which is two independent
  verdicts, without pretending hevm ran.

## kontrol: SUBSTITUTED. All four R-SEARCH-2 rungs, named.

  1 gemini-grounding: unreachable on this network. The endpoint
    generativelanguage.googleapis.com fails TLS here (task 1.11, ADR-004). Not a
    quota finding, a transport finding.
  2 WebSearch: 'kontrol install 2026 kup docker image runtimeverification getting
    started foundry' returned the official route: kup via kframework.org/install,
    then 'kup install kontrol'. That route was then attempted above, so the search
    succeeded and the install is what failed.
  3 DoH-pinned direct fetch: the installer itself downloads fine. kup is Nix-backed,
    and a Nix daemon install needs a systemd user session this distro does not
    provide. Docker, the documented alternative, is not integrated (E6).
  4 Browser render: not attempted, and here is why rather than as an excuse. The
    blocker is a daemon requirement on this machine, not a JavaScript-rendered page.
    Rendering the install page in a browser would return the same shell command that
    rung 2 already produced and rung 3 already ran.

  SUBSTITUTE: hevm 0.57.0, from argotorg/hevm, installed and PASSING 5 cap theorems
  in evidence/phase0/hevm.txt. That is a genuinely independent symbolic engine, not
  another halmos version, so tasks 1.4 and 7.7 get two independent engines as
  intended. kontrol would have been a THIRD opinion on the same property.

  WHAT IS ACTUALLY LOST, stated rather than glossed: kontrol's K semantics reason
  about unbounded loops and deeper call structures than a bounded symbolic run. None
  of the properties in this project involve unbounded loops, so the loss is real but
  narrow. If a future property needs loop reasoning, kontrol becomes required and
  Docker integration becomes the cheapest path to it.

## act (argotorg/act, formerly ethereum/act), task 1.6, NOT INSTALLED

R-SEARCH-2 rungs, all four named as the rule requires:
1. gemini-grounding / WebSearch: returned the repo, the 0.1 release post, and the Ethereum
   formal-verification overview. All agree there is one build route.
2. Primary source, the argotorg/act README: "Act builds with Nix." No cargo, apt, npm or pip
   route exists. The repo also MOVED from ethereum/act, the same migration that broke hevm.
3. DoH-pinned direct fetch of the releases page: NO prebuilt binary assets published. This is
   the decisive rung. hevm ships a static x86_64 binary; act ships none.
4. Browser render: not attempted, and this is stated rather than padded. A rendered page
   cannot produce a release asset that does not exist. Rungs 1-3 answered the question.

Cost of the only route: a Nix install (daemon mode needs systemd, only partially integrated
here per E6) plus a from-source GHC build of act and its solver dependencies.

CAPABILITY LOST, stated without minimising:
- A machine-checked specification in a language independent of Solidity. halmos and hevm
  properties are both written in Solidity, so a Solidity-level misconception could appear in
  both contract and property. act's separate spec language defends against that, and nothing
  installed here is a full substitute.
- Rocq/Coq extraction, so no interactive proof beyond SMT reach.

WHY ACCEPTABLE HERE: the invariants are small and arithmetic (bounded monotone accumulator,
sum equals parts, kill switch refuses all input), well inside SMT's decidable range, which is
why halmos and hevm both discharge them without bounding tricks. Not the class of property
that needs an interactive prover. The independent-language defence is partially recovered by
stating the same cap invariant in THREE formalisms: a halmos check_, an hevm prove_, and a
scribble annotation checked at runtime against a live contract.

Also worth stating: act's strongest EVM backend IS hevm, which is installed and driving five
theorems directly. Installing act would add a layer above a backend already in use.
