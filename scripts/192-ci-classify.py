"""Which gates can run in CI, and which genuinely cannot?

A CI pipeline that silently drops the gates it cannot run is worse than no pipeline: it reports green
over a smaller set than the reader assumes. So every gate is classified here, with the REASON, and
anything CI-incompatible is declared as a local-only gate in the README rather than quietly omitted.

Three disqualifiers, in order of how hard they are to fake:
  KEY     needs the deployer keystore. Cannot run in CI and must not: a funded key in CI secrets is
          a key one compromised action away from being drained.
  RPC     needs a live X Layer node. Could run in CI, but makes the pipeline fail on someone else's
          outage, and a gate that goes red for reasons unrelated to the diff trains people to ignore
          it.
  BROWSER needs the Browser pane (E11). rAF and setTimeout do not fire headless here.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(REPO, "scripts")

KEY_PAT = re.compile(r"keystore_pass|KEYFILE|--keystore|cast send|cast wallet")
RPC_PAT = re.compile(r"XLAYER_\w*RPC|--rpc-url|rpc\.xlayer|testrpc\.xlayer|cast (call|receipt|code|chain-id|block-number)")
BROWSER_PAT = re.compile(r"Browser pane|measure-density|dashboard_audit|failure_paths_audit|inject_provider|click_counter|landing_audit|exit_controls_audit")


def classify(path):
    try:
        t = open(path, encoding="utf-8", errors="replace").read()
    except Exception:
        return None
    tags = []
    if KEY_PAT.search(t):
        tags.append("KEY")
    if RPC_PAT.search(t):
        tags.append("RPC")
    if BROWSER_PAT.search(t):
        tags.append("BROWSER")
    return tags


def main():
    rows = []
    for name in sorted(os.listdir(SCRIPTS)):
        if not (name.endswith(".sh") or name.endswith(".py")):
            continue
        tags = classify(os.path.join(SCRIPTS, name))
        if tags is None:
            continue
        rows.append((name, tags))

    ci_ok = [n for n, t in rows if not t]
    blocked = [(n, t) for n, t in rows if t]

    print(f"total scripts: {len(rows)}")
    print(f"CI-runnable (no external dependency): {len(ci_ok)}")
    print(f"blocked: {len(blocked)}")
    print()
    print("=== BLOCKED, with reason ===")
    for n, t in blocked:
        print(f"  {'+'.join(t):18} {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
