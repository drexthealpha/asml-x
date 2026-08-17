"""Check every INSTALLED ui-v2 version against its pin, and fail if any differ.

Replaces a grep over pnpm-lock.yaml that reported react as 19.2.18 (that is @types/react) and
vite as 4.3.3 (that is tailwindcss), under a PASS verdict claiming versions were as pinned.
Substring matching over a lockfile is not a parser.

Input: `pnpm list --depth 0 --json` output at /home/zulab/ui-tree.json.
Exit 0 only if every pinned package is installed at exactly its pinned version.
"""
import json
import sys

TREE = "/home/zulab/ui-tree.json"

# The pins, duplicated here on purpose: this file is the CHECK, so it must state independently
# what it expects rather than reading the same package.json the installer read. If package.json
# is edited without updating this list, the check fails and that is the correct outcome.
EXPECTED = {
    "react": "19.2.8",
    "react-dom": "19.2.8",
    "@tanstack/react-table": "8.21.3",
    "lightweight-charts": "5.2.0",
    "lucide-react": "1.31.0",
    "framer-motion": "13.1.0",
    "class-variance-authority": "0.7.1",
    "clsx": "2.1.1",
    "tailwind-merge": "3.6.0",
    "@types/react": "19.2.18",
    "@types/react-dom": "19.2.4",
    "@vitejs/plugin-react": "5.2.0",
    "typescript": "5.9.3",
    "vite": "7.3.6",
    "tailwindcss": "4.3.3",
    "@tailwindcss/vite": "4.3.3",
}


def main():
    try:
        raw = json.load(open(TREE, encoding="utf-8"))
    except Exception as e:
        print(f"    could not read the installed tree: {e}")
        return 1

    # `pnpm list --json` returns a list of workspace projects.
    proj = raw[0] if isinstance(raw, list) else raw
    installed = {}
    for section in ("dependencies", "devDependencies", "optionalDependencies"):
        for name, info in (proj.get(section) or {}).items():
            installed[name] = info.get("version") if isinstance(info, dict) else str(info)

    bad = 0
    print("    %-28s %-12s %-12s %s" % ("package", "pinned", "installed", "match"))
    for name in sorted(EXPECTED):
        want = EXPECTED[name]
        got = installed.get(name, "ABSENT")
        ok = got == want
        if not ok:
            bad += 1
        print("    %-28s %-12s %-12s %s" % (name, want, got, "yes" if ok else "NO"))

    extra = sorted(set(installed) - set(EXPECTED))
    if extra:
        print(f"    direct dependencies not in the pin list: {', '.join(extra)}")
        bad += len(extra)

    print()
    if bad:
        print(f"    {bad} MISMATCH(ES). The pins and the installed tree disagree.")
        return 1
    print(f"    all {len(EXPECTED)} pinned packages installed at exactly their pinned version.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
