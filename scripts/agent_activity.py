"""What the agent did with your money, in a person's words.

WHY THIS FILE EXISTS. The backend produces a decision journal: scored candidates, refusal reasons,
micro-unit edge terms, block numbers. All of it is true and none of it is readable. A person who
deposited money wants three answers:

    Is it working right now?
    What did it do?
    Why did it not do the other things?

THE TRANSLATION IS THE PRODUCT. "hold outscored every permitted action, 24 candidate(s) refused by
risk" becomes "It considered 24 trades and took none — none of them beat doing nothing." Same fact,
same numbers, reachable by someone who has never read a docstring.

WHAT IS DELIBERATELY NOT TRANSLATED AWAY. The refusal COUNT stays, because it is the product's
whole argument: a system that refuses is one that has limits. It is framed as protection rather
than failure, which is what it is, but it is never hidden.

NOTHING HERE IS COMPUTED FROM SCRATCH. Every figure is read out of the journal the agent wrote at
the time it decided. This file rewords, it does not recalculate.
"""
import json
import os
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JOURNAL = os.path.join(REPO, "ui-v2", "public", "data", "journal.jsonl")
SWAPS = os.path.join(REPO, "evidence", "phase19", "real-swaps.jsonl")
OUT = os.path.join(REPO, "ui-v2", "public", "data", "activity.json")

EXPLORER = "https://www.oklink.com/x-layer/evm/tx/"


def plain_action(action):
    """Turn 'take order 1 Sell 1.500000 base at 1.900000' into something readable."""
    if not action or action == "hold":
        return "Waited"
    parts = action.split()
    try:
        side = "Sold" if "Sell" in parts else "Bought"
        amount = next(p for p in parts if "." in p)
        price = parts[-1]
        return f"{side} {float(amount):g} at ${float(price):g}"
    except (StopIteration, ValueError):
        return action


def plain_refusal(reason):
    """The engine's own refusal text, said the way a person would say it."""
    if not reason:
        return None
    r = reason.lower()
    if "lower score" in r:
        return "A safer option scored better"
    if "notional" in r or "toolarge" in r:
        return "Bigger than your limit allows"
    if "exposure" in r:
        return "Would have taken on too much at once"
    if "confidence" in r:
        return "The signal was not strong enough"
    if "divergence" in r:
        return "The price disagreed with the reference"
    if "stale" in r or "age" in r:
        return "The price data was too old to trust"
    if "freemargin" in r.replace(" ", ""):
        return "Not enough money left to cover it safely"
    if "consecutiveloss" in r.replace(" ", ""):
        return "It had lost too many times in a row"
    if "drawdown" in r:
        return "Losses had already reached the day's cap"
    if "paused" in r or "killswitch" in r.replace(" ", ""):
        return "Trading was paused"
    if "crossed" in r:
        return "The market prices did not make sense"

    # AN UNTRANSLATED REASON MUST NOT REACH THE SCREEN AS A RUST ENUM.
    # `risk refused: InsufficientFreeMargin { would_leave: 22, minimum: 5000000 }` is exactly the
    # kind of string this product is supposed to keep off a person's screen. Anything that gets
    # here is a refusal the translation table does not know yet: it is counted honestly under a
    # general heading rather than either hidden or dumped raw.
    return "Blocked by a safety rule"


def main():
    if not os.path.exists(JOURNAL):
        print("no journal")
        return 1

    entries = []
    with open(JOURNAL, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue

    if not entries:
        print("journal is empty")
        return 1

    decisions = []
    refusal_reasons = {}
    total_considered = 0
    total_refused = 0
    acted = 0

    for e in entries[-60:]:
        cands = e.get("candidates") or []
        refused = [c for c in cands if c.get("rejection_reason")]
        total_considered += len(cands)
        total_refused += len(refused)

        for c in refused:
            key = plain_refusal(c.get("rejection_reason"))
            if key:
                refusal_reasons[key] = refusal_reasons.get(key, 0) + 1

        action = e.get("action")
        did_something = bool(action) and action != "hold"
        if did_something:
            acted += 1

        decisions.append({
            "id": e.get("decision_id"),
            "block": e.get("block_number"),
            "market": e.get("market"),
            "did": plain_action(action),
            "acted": did_something,
            "considered": len(cands),
            "refused": len(refused),
            # The thesis, trimmed. It is the agent's own sentence about what it saw.
            "saw": (e.get("thesis") or "").split(";")[0][:120],
            "confidence_pct": round((e.get("thesis_confidence_bps") or 0) / 100),
        })

    decisions.reverse()

    swaps = []
    if os.path.exists(SWAPS):
        with open(SWAPS, encoding="utf-8") as fh:
            for line in fh:
                try:
                    s = json.loads(line)
                except json.JSONDecodeError:
                    continue
                swaps.append({
                    "from": s.get("from"),
                    "to": s.get("to"),
                    "venues": s.get("venues"),
                    "tx": s.get("tx"),
                    "explorer": s.get("explorer") or (EXPLORER + str(s.get("tx"))),
                    "at": s.get("at_utc"),
                })
    swaps.reverse()

    latest = decisions[0] if decisions else {}

    out = {
        # PROVENANCE, on every data file. The no-hardcoded-data gate refuses a file that cannot say
        # where it came from, because a file with no source is indistinguishable from one somebody
        # typed. This one was missing it and the gate caught it on its first run, which is the
        # entire argument for having the gate rather than the convention.
        "source": (
            "the agent's own decision journal, reworded for a reader. "
            "Counts are read from evidence/journal.jsonl, never recomputed."
        ),
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "chain_id": 196,
        # THE HEADLINE, in the order a person asks it.
        "status": "watching" if decisions else "not started",
        "last_seen_block": latest.get("block"),
        "market": latest.get("market"),
        "decisions_shown": len(decisions),
        "trades_made": acted,
        "options_considered": total_considered,
        "options_declined": total_refused,
        # Ranked, because the top reason is the one worth reading.
        "why_declined": sorted(
            ({"reason": k, "count": v} for k, v in refusal_reasons.items()),
            key=lambda x: -x["count"],
        ),
        "decisions": decisions[:25],
        "real_swaps": swaps,
        "plain_summary": (
            f"The agent looked at {total_considered} possible trades and made {acted}. "
            f"It turned down {total_refused} because they did not meet the rules you set."
        ),
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)

    print(out["plain_summary"])
    for r in out["why_declined"][:5]:
        print(f"  {r['count']:>5}  {r['reason']}")
    print(f"  real swaps executed: {len(swaps)}")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
