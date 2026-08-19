"""Regenerate the UI's chain manifest and journal from MAINNET only.

Called by scripts/210-mainnet-ui.sh. Split out of that script because the filtering has real edge
cases and CLAUDE.md E4 makes any of this unreliable inside a `wsl -- bash -c` invocation.

TWO REFUSALS ARE THE POINT OF THIS FILE, and both would otherwise be silent:

  1. If no mainnet entries exist, it writes NOTHING and exits non-zero. An empty journal on a
     product surface renders as "no decisions", which looks like a working product with a quiet
     agent rather than a broken pipeline. That is the worst possible failure mode.
  2. If the mainnet manifest is missing an address, it names which one and exits. A manifest with a
     null address renders a link to nowhere.

NAMING. The testnet manifest calls its tokens "MockERC20 tBASE" and "MockERC20 tQUOTE", which is
accurate for testnet and is the label a reader sees. On mainnet the same contracts are aBASE and
aQUOTE, and calling them "Mock" on a live chain would be both wrong and alarming. They are still
`self_deployed: true`, because they are, and that badge is not something this file may remove.
"""
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI = os.path.join(REPO, "ui-v2", "public", "data")
EVIDENCE = os.path.join(REPO, "evidence", "phase19", "mainnet-ui.txt")

EXPLORER_TX = "https://www.oklink.com/x-layer/evm/tx/"
EXPLORER_ADDR = "https://www.oklink.com/x-layer/evm/address/"

# (manifest key, UI name, role, is it ours)
CONTRACTS = [
    ("tQUOTE", "aQUOTE", "Quote asset the vault accounts in", True),
    ("tBASE", "aBASE", "Base asset the agent trades", True),
    ("venue", "OrderBookVenue", "Execution venue", True),
    ("riskGuard", "RiskGuard", "On-chain limit store. Limits can only tighten", True),
    ("batchExecutor", "BatchExecutor", "Submits approved actions, and only approved actions", True),
    ("feeCollector", "FeeCollector", "Usage fee, capped at 100 bps by the contract", True),
    ("agentVault", "AgentVault", "Your deposits. Withdrawal works while paused", True),
    ("rwaVault", "RwaVault", "The RWA vault, live on mainnet", True),
    ("rwaRiskGuard", "RwaRiskGuard", "RWA-specific refusals, including the peg band", True),
]


def main():
    floor = int(sys.argv[1]) if len(sys.argv) > 1 else 60_000_000

    with open(os.path.join(REPO, "deployments-mainnet.json"), encoding="utf-8") as fh:
        m = json.load(fh)

    missing = [k for k, _, _, _ in CONTRACTS if not m.get(k)]
    if missing:
        print(f"ABORT: deployments-mainnet.json has no address for: {', '.join(missing)}")
        return 1

    # ------------------------------------------------------------------ journal, mainnet only
    src = os.path.join(REPO, "evidence", "journal.jsonl")
    kept, skipped, bad = [], 0, 0
    with open(src, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                bad += 1
                continue
            if int(d.get("block_number", 0)) >= floor:
                kept.append(line)
            else:
                skipped += 1

    if not kept:
        print(
            f"ABORT: no journal entries at or above block {floor}. The mainnet run produced\n"
            "nothing, so the UI journal is left untouched. Writing an empty one would render as\n"
            "'no decisions' on a live product, which reads as a quiet agent rather than a broken\n"
            "pipeline."
        )
        return 1

    with open(os.path.join(UI, "journal.jsonl"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(kept) + "\n")

    # ------------------------------------------------------------------ deployments manifest
    out = {
        "chain_id": m["chainId"],
        "chain_name": "X Layer",
        "network": "mainnet",
        "rpc_url": m["rpc"],
        "explorer_base": EXPLORER_TX,
        "explorer_address_base": EXPLORER_ADDR,
        "deploy_block": m.get("deployBlock"),
        "source": "deployments-mainnet.json",
        "verified_by": "bash scripts/210-mainnet-ui.sh",
        "deployments": [
            {
                "name": name,
                "address": m[key],
                "role": role,
                "self_deployed": ours,
                # The badge stays. These contracts ARE deployed by this project, and a script whose
                # job is relabelling the network is not allowed to quietly relabel provenance too.
                "explicit_standin_marker": False,
            }
            for key, name, role, ours in CONTRACTS
        ],
    }
    with open(os.path.join(UI, "deployments.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)

    blocks = [json.loads(k)["block_number"] for k in kept]
    report = (
        f"UI regenerated from mainnet\n"
        f"  chain          {out['chain_id']} ({out['network']})\n"
        f"  rpc            {out['rpc_url']}\n"
        f"  contracts      {len(CONTRACTS)}, including RwaVault and RwaRiskGuard\n"
        f"  journal kept   {len(kept)} mainnet entries\n"
        f"  journal cut    {skipped} testnet entries below block {floor}\n"
        f"  malformed      {bad}\n"
        f"  block range    {min(blocks)} to {max(blocks)}\n"
    )
    os.makedirs(os.path.dirname(EVIDENCE), exist_ok=True)
    with open(EVIDENCE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("```\n" + report + "```\n")
    print(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
