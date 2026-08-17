"""Measure, for every submitted decision, the gap between the block read and the block landed.

Task 4.8. The point is NOT to pass a threshold. It is to establish that the direction always holds
(a transaction cannot land before the state it was decided on) and to report the magnitude as the
signing-path latency it is.

Every receipt is fetched from chain with cast. Nothing is read from a cached table.
"""
import json
import subprocess
import sys

REPO = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"
J = f"{REPO}/ui-v2/public/data/journal.jsonl"
RPC = "https://testrpc.xlayer.tech"


def receipt_block(tx):
    try:
        out = subprocess.run(
            ["cast", "receipt", tx, "--rpc-url", RPC, "--json"],
            capture_output=True, text=True, timeout=60,
        ).stdout
        d = json.loads(out)
        return int(d["blockNumber"], 16), d.get("status")
    except Exception:
        return None, None


def main():
    rows = [json.loads(l) for l in open(J, encoding="utf-8") if l.strip()]
    subs = sorted(
        (r for r in rows if r.get("tx_hash")),
        key=lambda r: int(r["decision_id"]),
    )
    if not subs:
        print("  no submitted decisions in the staged journal")
        return 1

    drifts = []
    negative = []
    failed = []
    unresolved = []
    for r in subs:
        read_block = int(r["block_number"])
        blk, status = receipt_block(r["tx_hash"])
        if blk is None:
            unresolved.append(r["tx_hash"])
            continue
        if status not in ("0x1", 1, "0x01"):
            failed.append((r["decision_id"], status))
        d = blk - read_block
        drifts.append(d)
        if d < 0:
            negative.append((r["decision_id"], read_block, blk))

    drifts.sort()
    n = len(drifts)
    print(f"  submitted decisions checked against chain: {n} of {len(subs)}")
    if unresolved:
        print(f"  UNRESOLVED transactions: {len(unresolved)}")
        for t in unresolved[:5]:
            print(f"    {t}")
    if failed:
        print(f"  transactions NOT status 0x1: {len(failed)} -> {failed[:5]}")
    if n:
        print(f"  drift blocks  min {drifts[0]}  median {drifts[n // 2]}  max {drifts[-1]}")
        print(f"  at 1.0s per block that is {drifts[0]}s to {drifts[-1]}s from read to landing")
        print(f"  landed before the read (impossible if the seam is sound): {len(negative)}")
        for d in negative[:5]:
            print(f"    decision {d[0]}: read {d[1]}, landed {d[2]}")

    ok = n > 0 and not negative and not failed and not unresolved
    print()
    print("  DIRECTION HOLDS FOR ALL" if ok else "  CHECK FAILED, see the rows above")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
