"""Generate ui-v2/public/data/deployments.json from docs/verified/deployments.md.

Generated rather than hand-written for two reasons:

1. A contract that is not in the verified document cannot appear in the UI. The document is the
   one that was checked against chain by scripts/67-verify-deployments.sh.
2. `self_deployed` is derived from the document's own "SELF-DEPLOYED STAND-IN" labelling and from
   the fact that every address in it was deployed by this project's deployer. Deciding that flag in
   a component, or typing it here from memory, is how a venue number ends up rendering without a
   provenance badge, which task 4.6 explicitly fails on.
"""
import json
import os
import re
import sys

REPO = "/mnt/c/Users/zulab/OneDrive/Desktop/ASML-X"
DOC = os.path.join(REPO, "docs/verified/deployments.md")
OUT = os.path.join(REPO, "ui-v2/public/data/deployments.json")

ROW = re.compile(r"^\|\s*(?P<name>[^|]+?)\s*\|\s*`(?P<addr>0x[0-9a-fA-F]{40})`\s*\|\s*(?P<role>[^|]*)\|")


def main():
    if not os.path.exists(DOC):
        print(f"  MISSING {DOC}")
        return 1

    text = open(DOC, encoding="utf-8").read()
    rows = []
    for line in text.splitlines():
        m = ROW.match(line.strip())
        if not m:
            continue
        name = m.group("name").strip()
        # The document marks stand-ins inline. Keep the marker out of the display name and turn it
        # into the flag instead.
        marker = "SELF-DEPLOYED STAND-IN" in name or "SELF-DEPLOYED STAND-IN" in m.group("role")
        clean = name.replace("`SELF-DEPLOYED STAND-IN`", "").replace("SELF-DEPLOYED STAND-IN", "").strip()
        rows.append(
            {
                "name": clean,
                "address": m.group("addr"),
                "role": m.group("role").strip(),
                # EVERY address in this document was deployed by this project's own deployer, which
                # scripts/67-verify-deployments.sh re-checks against chain. So the flag is true for
                # all of them, and the explicit stand-in marker is kept as part of the role text so
                # the stronger claim is not lost.
                "self_deployed": True,
                "explicit_standin_marker": marker,
            }
        )

    if not rows:
        print("  NO ROWS parsed from the deployments document, refusing to write an empty manifest")
        return 1

    manifest = {
        "chain_id": 1952,
        "rpc_url": "https://testrpc.xlayer.tech",
        "explorer_base": "https://www.oklink.com/x-layer-testnet/tx/",
        "source": "docs/verified/deployments.md",
        "verified_by": "bash scripts/67-verify-deployments.sh",
        "deployments": rows,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")

    print(f"  parsed {len(rows)} deployment row(s) from docs/verified/deployments.md")
    for r in rows:
        marker = " (explicit stand-in marker)" if r["explicit_standin_marker"] else ""
        print(f"    {r['name']:<26} {r['address']}  self_deployed=True{marker}")
    print(f"  wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
