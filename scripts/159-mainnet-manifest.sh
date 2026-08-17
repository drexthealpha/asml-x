#!/usr/bin/env bash
# Task 12.7: publish the mainnet transactions where the UI and the JUDGE-GUIDE can read them.
#
# One generated file, two surfaces. A hand-maintained list in the README and another in a component
# is two places to go stale, and the addresses in this project have already gone stale in three
# separate files once (Phase 7).
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

MJ="$REPO/deployments-mainnet.json"
UIOUT="$REPO/ui-v2/public/data/mainnet.json"
RPC="https://rpc.xlayer.tech"
mkdir -p "$(dirname "$UIOUT")"

a() { python3 -c "import json;print(json.load(open('$MJ'))['$1'])"; }

# The transactions this phase produced, gathered from the evidence files that recorded them so the
# manifest cannot claim a hash no evidence file supports.
python3 - "$MJ" "$UIOUT" "$REPO" "$RPC" <<'PY'
import json, os, re, sys

mj, out, repo, rpc = sys.argv[1:5]
d = json.load(open(mj))

# Scrape hashes out of the phase 12 evidence, so every entry traces to a document.
found = []
seen = set()
ev = f"{repo}/evidence/phase12"
labels = {
    "mainnet-loop.md": "agent loop: perceive, thesis, risk gate, execute",
    "mainnet-fee.md": "fee charged, decoded from the receipt",
    "mainnet-refusal.md": "risk refusal, reverted on chain",
    "mainnet-personal.md": "user deposit, agent action, withdrawal",
}
for fn, label in labels.items():
    p = os.path.join(ev, fn)
    if not os.path.exists(p):
        continue
    for h in re.findall(r"0x[0-9a-f]{64}", open(p, encoding="utf-8").read()):
        if h in seen:
            continue
        seen.add(h)
        found.append({"hash": h, "what": label, "source": f"evidence/phase12/{fn}"})

doc = f"{repo}/docs/verified/deployments-mainnet.md"
deploys = []
if os.path.exists(doc):
    for h in re.findall(r"0x[0-9a-f]{64}", open(doc, encoding="utf-8").read()):
        if h not in seen:
            seen.add(h)
            deploys.append({"hash": h, "what": "contract deployment",
                            "source": "docs/verified/deployments-mainnet.md"})

manifest = {
    "chainId": 196,
    "chainName": "X Layer",
    "rpc": rpc,
    # Verified in task 11.1 by LOADING it in a real browser: the /address form redirects to
    # /evm/address, so the canonical form is used directly rather than relying on a redirect.
    "explorerTx": "https://www.oklink.com/x-layer/evm/tx/",
    "explorerAddress": "https://www.oklink.com/x-layer/evm/address/",
    "contracts": [
        {"name": "aQUOTE", "address": d["tQUOTE"]},
        {"name": "aBASE", "address": d["tBASE"]},
        {"name": "OrderBookVenue", "address": d["venue"]},
        {"name": "RiskGuard", "address": d["riskGuard"]},
        {"name": "FeeCollector", "address": d["feeCollector"]},
        {"name": "BatchExecutor", "address": d["batchExecutor"]},
        {"name": "AgentVault", "address": d["agentVault"]},
    ],
    "transactions": found + deploys,
}
json.dump(manifest, open(out, "w"), indent=2)
print(f"wrote {out}")
print(f"  contracts    {len(manifest['contracts'])}")
print(f"  transactions {len(manifest['transactions'])}")
PY

echo "written: $UIOUT"
