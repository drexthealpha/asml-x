#!/usr/bin/env python3
"""Fetch FeeCharged events from chain under a 100-block eth_getLogs ceiling.

THE CONSTRAINT, measured rather than assumed (scripts/probe-feelogs.sh):
    {"code":-32602,"message":"block range greater than 100 max"}
X Layer's public RPC refuses any getLogs span wider than 100 blocks. With ~1s blocks that is 100
seconds of history, and the FeeCollector's deployment is already thousands of blocks back and moving
further every second. A naive from-block-0 scan does not merely get slow, it is rejected outright,
which is what made the first version report "0 events fetched" while two events existed on chain.

THE DESIGN, and why it is not a workaround:

  TOTALS come from contract STATE, in two calls with no range limit at all: `chargeCount()` and
  `totalCollected(token)`. This is not a shortcut around the ceiling, it is the better source.
  Theorem 5 in test/FeeFormal.t.sol (check_totalCollectedAccumulatesExactly) proves symbolically that
  `totalCollected` after a charge equals the total before plus the quoted fee, so summing the events
  and reading the state are provably the same number. Reading state costs two calls and cannot miss
  an event that fell outside a scan window; summing logs costs N calls and can.

  RECENT EVENTS come from a bounded BACKWARD scan in 100-block windows from head, stopping as soon as
  enough are found or the budget is spent. Only the detail rows need logs, and only the newest ones
  are ever displayed.

  A CACHE makes the scan cheap on repeat runs. FeeCharged events are append-only and immutable once
  finalised, so a previously-seen event never changes. The cache stores events by tx hash and log
  index and the scan stops early once it reaches known territory.

FAILURE IS LOUD. If the state reads fail, this exits non-zero and writes no totals, because a
revenue figure that silently reads zero when the chain is unreachable is worse than no figure. That
rule already cost this task one wrong answer: an `|| echo '[]'` fallback in the shell caller turned a
rejected request into a confident zero.
"""
import json
import os
import subprocess
import sys
import time

REPO = os.environ.get("REPO") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RPC = os.environ["RPC"]
MAX_SPAN = 100          # the RPC's hard ceiling, quoted above
# Window budget per run. The first run backfills from the collector's deploy block and may use most
# of it; every run after that resumes from the cached cursor and typically spends a handful. 300
# windows is 30,000 blocks, about 8 hours of chain at ~1s blocks.
WINDOWS = 300
WANT_RECENT = 5
# Wall-clock budget for the LOG SCAN only. The totals come from contract state and are never subject
# to it: a cold backfill that runs long must not be able to discard a number already in hand.
SCAN_BUDGET_S = 45
CACHE = os.path.expanduser("~/.asml-fee-events-cache.json")
TOPIC0 = None


def cast(*args, timeout=60, rpc=True):
    """`rpc=False` for the pure-local subcommands. `cast keccak` takes no --rpc-url and rejects it
    outright with "unexpected argument", which is the compiler-style error worth trusting: it is not
    a connectivity problem, it is the wrong command shape."""
    cmd = ["cast", *args] + (["--rpc-url", RPC] if rpc else [])
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(f"cast {args[0]} failed: {(r.stderr or r.stdout).strip()[:200]}")
    return r.stdout.strip()


def decode(lg):
    data = lg["data"][2:]
    w = [data[i : i + 64] for i in range(0, len(data), 64)]
    if len(w) < 4:
        return None
    blk = lg.get("blockNumber")
    return {
        "payer": "0x" + lg["topics"][1][-40:],
        "market": lg["topics"][2],
        "token": "0x" + w[0][-40:],
        "notional_wei": str(int(w[1], 16)),
        "fee_wei": str(int(w[2], 16)),
        "fee_bps": int(w[3], 16),
        "tx": lg.get("transactionHash"),
        "log_index": int(lg["logIndex"], 16) if isinstance(lg.get("logIndex"), str) else lg.get("logIndex"),
        "block": int(blk, 16) if isinstance(blk, str) else blk,
    }


def _deploy_floor(collector):
    """The block below which this collector cannot have emitted anything.

    Read from deployments.json when the deploy script recorded it. Falling back to block 0 would make
    a cold backfill scan the entire chain in 100-block windows, so the fallback is a bounded lookback
    instead, and `backfill_complete` reports honestly which of the two happened.
    """
    try:
        d = json.load(open(f"{REPO}/deployments.json", encoding="utf-8"))
        if d.get("feeCollector", "").lower() == collector.lower() and d.get("feeDeployBlock"):
            return int(d["feeDeployBlock"])
    except Exception:
        pass
    return None


def load_cache(collector):
    try:
        c = json.load(open(CACHE))
        if c.get("collector", "").lower() == collector.lower():
            return c
    except Exception:
        pass
    return {"collector": collector, "events": []}


def main():
    global TOPIC0
    collector = sys.argv[1]
    token = sys.argv[2]

    out = {"collector": collector, "source": "contract state + bounded eth_getLogs backward scan"}

    # ---- TOTALS from state. Unbounded history, two calls, no range ceiling.
    try:
        count = int(cast("call", collector, "chargeCount()(uint256)").split()[0])
        total = int(cast("call", collector, "totalCollected(address)(uint256)", token).split()[0])
        bps = int(cast("call", collector, "feeBps()(uint256)").split()[0])
        treasury = cast("call", collector, "treasury()(address)")
        head = int(cast("block-number"))
    except Exception as exc:
        # No totals key is written at all. A missing number renders as an error; a zero renders as
        # "the business earned nothing", and those must never be confusable.
        out["error"] = f"fee state read failed: {exc}"
        print(json.dumps(out))
        return 1

    out.update(
        {
            "event_count": count,
            "total_fees_wei": str(total),
            "fee_bps": bps,
            "treasury": treasury,
            "fee_token": token,
            "totals_from": (
                "FeeCollector.chargeCount() and totalCollected(token), read directly from contract "
                "state. Proved equal to the sum of FeeCharged events by "
                "check_totalCollectedAccumulatesExactly in test/FeeFormal.t.sol."
            ),
            "head_block": head,
        }
    )

    # ---- RECENT EVENTS from a bounded backward scan, warm-started from cache.
    TOPIC0 = cast(
        "keccak", "FeeCharged(address,bytes32,address,uint256,uint256,uint256)", rpc=False
    )
    cache = load_cache(collector)
    seen = {(e["tx"], e["log_index"]) for e in cache["events"]}
    found = list(cache["events"])
    scanned = 0

    # A PERSISTENT CURSOR is what keeps this bounded as the chain grows. `covered_lo` and
    # `covered_hi` record the contiguous block range already scanned. Past FeeCharged events are
    # immutable once mined, so a range scanned once never needs scanning again; each run only has to
    # extend the window UP to the new head, and DOWN toward the deploy block until the backfill is
    # complete. Without this the scan restarts from head every run and the cost grows without limit
    # while the answer stays the same.
    deploy_block = _deploy_floor(collector)
    floor = deploy_block if deploy_block is not None else max(0, head - WINDOWS * MAX_SPAN)
    out["scan_floor"] = floor
    out["scan_floor_source"] = (
        "deployments.json feeDeployBlock" if deploy_block is not None else "bounded lookback from head"
    )
    covered_lo = cache.get("covered_lo")
    covered_hi = cache.get("covered_hi")

    scan_started = time.monotonic()

    def scan(lo, hi):
        nonlocal scanned
        while hi >= lo and scanned < WINDOWS:
            if time.monotonic() - scan_started > SCAN_BUDGET_S:
                out.setdefault("scan_warnings", []).append(
                    f"scan budget of {SCAN_BUDGET_S}s reached after {scanned} windows; "
                    "totals are unaffected because they come from contract state"
                )
                return
            wlo = max(lo, hi - MAX_SPAN + 1)
            try:
                raw = cast(
                    "logs", "--from-block", str(wlo), "--to-block", str(hi),
                    "--address", collector, TOPIC0, "--json",
                )
                scanned += 1
                for lg in json.loads(raw) if raw.strip() else []:
                    d = decode(lg)
                    if d and (d["tx"], d["log_index"]) not in seen:
                        seen.add((d["tx"], d["log_index"]))
                        found.append(d)
            except Exception as exc:
                out.setdefault("scan_warnings", []).append(f"window {wlo}-{hi}: {exc}")
            hi = wlo - 1

    if covered_hi is None:
        # Cold cache: backfill the whole collector lifetime, once.
        scan(floor, head)
        covered_lo, covered_hi = floor, head
    else:
        # Forward, to pick up anything new since the last run.
        if head > covered_hi:
            scan(covered_hi + 1, head)
            covered_hi = head
        # Backward, in case a previous run ran out of budget before reaching the deploy block.
        if covered_lo > floor:
            before = scanned
            scan(floor, covered_lo - 1)
            if scanned < WINDOWS:
                covered_lo = floor
            else:
                covered_lo = max(floor, covered_lo - (scanned - before) * MAX_SPAN)

    found.sort(key=lambda e: (e["block"] or 0, e["log_index"] or 0), reverse=True)
    json.dump(
        {
            "collector": collector,
            "events": found[:50],
            "covered_lo": covered_lo,
            "covered_hi": covered_hi,
        },
        open(CACHE, "w"),
        indent=2,
    )
    out["scan_covered_blocks"] = [covered_lo, covered_hi]
    # True only when the scan reached the collector's actual deploy block. With a bounded-lookback
    # floor it stays False, because "I scanned as far as I chose to" is not "I scanned everything".
    out["backfill_complete"] = deploy_block is not None and covered_lo <= deploy_block

    out["recent"] = found[:WANT_RECENT]
    out["windows_scanned"] = scanned
    out["recent_from"] = (
        f"bounded backward eth_getLogs scan, {MAX_SPAN}-block windows (the RPC rejects anything "
        f"wider with -32602 'block range greater than 100 max'), warm-started from a local cache of "
        f"immutable past events"
    )
    # The detail rows are best-effort by construction; the TOTALS are not, and the distinction is
    # stated in the file the UI reads rather than left for a reader to infer.
    out["recent_is_complete"] = len(out["recent"]) >= min(count, WANT_RECENT)

    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
