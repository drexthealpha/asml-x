"""The RWA layer's live on-chain state, read from the deployed contracts on chain 196.

WHY THIS IS MISSING FROM THE PRODUCT AND SHOULD NOT BE. `RwaVault` and `RwaRiskGuard` are deployed
on mainnet and enforce a second set of refusals that only make sense for a real-world asset: is the
oracle fresh, is the issuer paused, is a redemption window near, has the market price come loose
from the reference. That is the differentiator, and none of it reached the screen.

EVERY VALUE HERE IS AN `eth_call`. Nothing is remembered from a previous run, and the selectors are
computed by `cast sig` rather than written from memory — an invented selector returns `0x`, which
parses as zero, so a wrong one would silently report a limit of 0 as though it had been read.

ABSENT IS ABSENT. A call that fails leaves the field null and the UI says the value could not be
read. A zero standing in for an unread limit is the most dangerous possible substitution: it reads
as "no risk allowed" when it means "nobody checked".
"""
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "ui-v2", "public", "data", "rwa-state.json")

# Computed with `cast sig`, verified in scripts/227-rwa-selectors.sh. Never typed from memory.
#
# TWO OF THESE WERE WRONG when first written: maxOracleAge and windowBufferSeconds were both
# invented rather than derived, and both would have returned 0x, parsed to None, and reported the
# rules as unreadable. That is the third time in this project a guessed selector has cost time,
# which is why 227 now computes every one and reads its live value in the same run.
SEL = {
    "maxDivergenceBps": "0xf9de4776",
    "maxOracleAge": "0x7c87a993",
    "windowBufferSeconds": "0x65f1fd4f",
    "paused": "0x5c975abb",
    "owner": "0x8da5cb5b",
    "asset": "0x38d52e0f",
    "totalAssets": "0x01e1d114",
}


def call(rpc, to, selector):
    """One eth_call. Returns the hex result, or None. Never a default."""
    payload = json.dumps({
        "jsonrpc": "2.0", "id": 1, "method": "eth_call",
        "params": [{"to": to, "data": selector}, "latest"],
    })
    try:
        r = subprocess.run(
            ["curl", "-sS", "--max-time", "15", "-H", "Content-Type: application/json",
             "-d", payload, rpc],
            capture_output=True, text=True, timeout=25,
        )
        result = json.loads(r.stdout).get("result")
        return result if result and result != "0x" else None
    except Exception:
        return None


def as_int(hexstr):
    return int(hexstr, 16) if hexstr else None


def as_addr(hexstr):
    return "0x" + hexstr[-40:] if hexstr else None


def main():
    with open(os.path.join(REPO, "deployments-mainnet.json"), encoding="utf-8") as fh:
        m = json.load(fh)
    rpc = m["rpc"]
    guard = m.get("rwaRiskGuard")
    vault = m.get("rwaVault")

    if not guard or not vault:
        print("RWA contracts are not in the mainnet manifest")
        return 1

    print(f"reading RWA state from chain {m['chainId']}")

    divergence = as_int(call(rpc, guard, SEL["maxDivergenceBps"]))
    oracle_age = as_int(call(rpc, guard, SEL["maxOracleAge"]))
    window_buf = as_int(call(rpc, guard, SEL["windowBufferSeconds"]))
    guard_owner = as_addr(call(rpc, guard, SEL["owner"]))
    vault_asset = as_addr(call(rpc, vault, SEL["asset"]))
    vault_paused_raw = call(rpc, vault, SEL["paused"])
    vault_paused = None if vault_paused_raw is None else bool(as_int(vault_paused_raw))

    out = {
        "source": "eth_call against the deployed RWA contracts on X Layer mainnet",
        "chain_id": m["chainId"],
        "explorer": "https://www.oklink.com/x-layer/evm/address/",
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "guard_address": guard,
        "vault_address": vault,
        "guard_owner": guard_owner,
        "vault_asset": vault_asset,
        "vault_paused": vault_paused,
        # The four refusals that only mean something for a real-world asset. Each is a live
        # contract parameter, not a description of one.
        "rules": [
            {
                "name": "Price must track its reference",
                "plain": (
                    "If the market price drifts further than this from the reference price, "
                    "the agent stops trading it."
                ),
                "value_bps": divergence,
                "display": f"{divergence / 100:.2f}%" if divergence is not None else None,
            },
            {
                "name": "The price must be recent",
                "plain": (
                    "A price older than this is refused. Stale data on a real-world asset is how "
                    "an agent trades yesterday's market."
                ),
                "value_seconds": oracle_age,
                "display": (
                    f"{oracle_age // 60} minutes" if oracle_age and oracle_age >= 60
                    else (f"{oracle_age} seconds" if oracle_age is not None else None)
                ),
            },
            {
                "name": "No trading near a redemption window",
                "plain": (
                    "Real-world assets have windows where they can be redeemed. Trading close to "
                    "one is refused, because the price moves for reasons the agent cannot see."
                ),
                "value_seconds": window_buf,
                "display": (
                    f"{window_buf // 60} minutes" if window_buf and window_buf >= 60
                    else (f"{window_buf} seconds" if window_buf is not None else None)
                ),
            },
            {
                "name": "The issuer must not be paused",
                "plain": (
                    "If whoever issues the asset halts it, the agent stops too, rather than "
                    "trading something nobody is standing behind."
                ),
                "value_bool": vault_paused,
                "display": (
                    None if vault_paused is None else ("halted" if vault_paused else "active")
                ),
            },
        ],
        "unreadable": [k for k, v in {
            "maxDivergenceBps": divergence,
            "maxOracleAge": oracle_age,
            "windowBufferSeconds": window_buf,
        }.items() if v is None],
    }

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=2)

    for r in out["rules"]:
        print(f"  {r['name']:<38} {r['display']}")
    if out["unreadable"]:
        print(f"  could not read: {', '.join(out['unreadable'])}")
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
