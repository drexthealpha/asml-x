#!/usr/bin/env bash
# Task 1.15 frontend stack. Scaffold ui-v2/ and prove the production build works with every
# version pinned by decision.
#
# THINKING: #37 visual/spatial (the stack has to support a dense terminal layout, which is why
# lightweight-charts and TanStack Table are in it and a component kit is not), #4 deductive
# (verified versions imply the lockfile, so the lockfile IS the evidence), #29 margin-of-safety
# (pin, do not float: a floating major is a build that breaks on submission day).
#
# THE FRONTEND GATE APPLIES AND IS NOT BEING BYPASSED. CLAUDE.md: no frontend code until
# evidence/ui-study.md exists with 30+ file:line citations. This task installs DEPENDENCIES and
# proves the toolchain builds. It writes no layout, no component, no chart, no table. The
# entry point is a deliberate three-line placeholder that names the gate, so that if anyone
# ships it by accident it is obvious rather than plausible. Every real component lands in
# Phase 4, after the study.
#
# EVIDENCE PATH declared before code: evidence/phase0/frontend-stack.txt, ui-v2/pnpm-lock.yaml
# PASS: `pnpm build` succeeds AND every pinned version is recorded from the LOCKFILE, not from
# package.json. package.json records what was asked for; the lockfile records what was
# installed, and those differ exactly when a range silently resolves elsewhere.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

OUT="$REPO/evidence/phase0/frontend-stack.txt"
mkdir -p "$(dirname "$OUT")"
UI="$REPO/ui-v2"

{
echo "Frontend stack scaffold, task 1.15"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo
echo "## Toolchain present"
echo "  node: $(node --version 2>&1 | head -1)"
echo "  npm:  $(npm --version 2>&1 | head -1)"
echo "  pnpm: $(pnpm --version 2>&1 | head -1 || echo ABSENT)"
} 2>&1 | tee "$OUT"

# TWO REAL FAILURES from the first run, both diagnosed by scripts/61c-node-probe.sh rather
# than by retrying:
#
# 1. `pnpm` on PATH was the WINDOWS install at /mnt/c/Users/zulab/AppData/Roaming/npm/pnpm,
#    reached over WSL interop. node itself is a proper Linux ELF v20.19.4, so the earlier
#    guess that a Windows node was involved was wrong; the problem is narrower and worse. That
#    pnpm wrote node_modules/.pnpm (the content store) and then created NO top-level package
#    directories and NO pnpm-lock.yaml. tsc then could not find react-dom/client because
#    react-dom genuinely was not there. The build failure was a real missing-module error, not
#    a types configuration problem, and "fixing" tsconfig would have chased a symptom.
# 2. pnpm's default isolated node-linker builds the tree out of SYMLINKS. This repo lives on a
#    Windows drive mounted through drvfs, where that symlink farm is exactly what did not
#    survive. `node-linker=hoisted` writes real directories instead.
#
# So: install a Linux pnpm into the user prefix and call it by ABSOLUTE PATH, because the
# Windows shim is earlier on PATH than anything a script can prepend reliably.
PNPM="/home/zulab/.npm-global/bin/pnpm"
if [ ! -x "$PNPM" ]; then
  echo "  installing a LINUX pnpm into the npm user prefix" | tee -a "$OUT"
  npm install -g pnpm 2>&1 | tail -3 | sed 's/^/    /' | tee -a "$OUT"
fi
{
echo "  pnpm in use: $PNPM"
echo "  version:     $("$PNPM" --version 2>&1 | tail -1 || echo ABSENT)"
echo "  (NOT the Windows shim at /mnt/c/.../AppData/Roaming/npm/pnpm, which produced a"
echo "   node_modules with a content store and no packages)"
} | tee -a "$OUT"

mkdir -p "$UI/src"

# package.json written directly rather than through `create-vite`, because the scaffolder is
# interactive and E4 plus a non-interactive shell make that a fight for no gain. Exact
# versions, no carets: the point of this task is that the build is reproducible.
#
# EVERY VERSION BELOW WAS QUERIED FROM THE REGISTRY, not recalled. R-SEARCH-1, and it mattered:
# my first draft pinned react 19.2.0, vite 7.1.9, tailwind 4.1.14, lucide 0.545.0 and
# framer-motion 12.23.24 from memory. The registry says react 19.2.8, tailwind 4.3.3,
# lucide-react 1.31.0 and framer-motion 13.1.0. Five wrong pins in one file, all caught by one
# probe (scripts/61b-npm-versions.sh) that cost less than one failed install.
#
# Two pins are DECISIONS, not just current versions, and both were confirmed to exist:
#   @tanstack/react-table 8.21.3, while latest is 9.1.2. v9 renames useReactTable and moves
#   the row models; the shadcn data-table examples are not v9-compatible. Decision in 1.15.
#   vite 7.3.6, while latest is 8.2.1. Vite 7 is the stack decided in 1.15. This forces
#   @vitejs/plugin-react 5.2.0, because plugin-react 6 declares peer vite ^8.0.0. That is a
#   real constraint read from the package's peerDependencies, not a guess.
# typescript 5.9.3 while latest is 7.0.2: TS 7 is a major this build has no reason to absorb
#   two weeks before a deadline, and `tsc -b` semantics are what the build script depends on.
cat > "$UI/package.json" <<'JSON'
{
  "name": "asml-x-ui",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "19.2.8",
    "react-dom": "19.2.8",
    "@tanstack/react-table": "8.21.3",
    "lightweight-charts": "5.2.0",
    "lucide-react": "1.31.0",
    "framer-motion": "13.1.0",
    "class-variance-authority": "0.7.1",
    "clsx": "2.1.1",
    "tailwind-merge": "3.6.0"
  },
  "devDependencies": {
    "@types/react": "19.2.18",
    "@types/react-dom": "19.2.4",
    "@vitejs/plugin-react": "5.2.0",
    "typescript": "5.9.3",
    "vite": "7.3.6",
    "tailwindcss": "4.3.3",
    "@tailwindcss/vite": "4.3.3"
  }
}
JSON

# node-linker=hoisted: real directories, not a symlink farm. Required because this tree lives on
# a drvfs-mounted Windows drive where pnpm's isolated linker left node_modules with a content
# store and no packages. Committed as .npmrc so the next clone on the same setup behaves the
# same way rather than depending on someone remembering a flag.
cat > "$UI/.npmrc" <<'NPMRC'
node-linker=hoisted
NPMRC

cat > "$UI/vite.config.ts" <<'TS'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// Tailwind v4 is a Vite PLUGIN, not a PostCSS config. v3's tailwind.config.js plus
// postcss.config.js is gone; configuration is CSS-first via @theme in index.css.
export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: { outDir: "dist", sourcemap: false },
});
TS

cat > "$UI/tsconfig.json" <<'JSON'
{
  "files": [],
  "references": [{ "path": "./tsconfig.app.json" }]
}
JSON

cat > "$UI/tsconfig.app.json" <<'JSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "noEmit": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true
  },
  "include": ["src"]
}
JSON

cat > "$UI/index.html" <<'HTML'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>ASML-X</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
HTML

cat > "$UI/src/index.css" <<'CSS'
@import "tailwindcss";
CSS

# The placeholder. Deliberately not a UI. It exists to give tsc and vite something real to
# compile, and it names the gate so that shipping it by accident is impossible to miss.
cat > "$UI/src/main.tsx" <<'TSX'
import { createRoot } from "react-dom/client";
import "./index.css";

// FRONTEND GATE PLACEHOLDER, task 1.15.
// No layout, component, chart or table is written until evidence/ui-study.md exists with 30+
// file:line citations from HypeTerminal. This file only proves the toolchain compiles and
// builds. Phase 4 replaces it.
const root = document.getElementById("root");
if (root) {
  createRoot(root).render(
    <pre>ASML-X ui-v2 toolchain check. Awaiting evidence/ui-study.md before any UI.</pre>,
  );
}
TSX

{
echo
echo "## Installing, exact versions, no ranges"
} | tee -a "$OUT"
cd "$UI"
rm -rf "$UI/node_modules"
timeout 900 "$PNPM" install 2>&1 | tail -14 | sed 's/^/  /' | tee -a "$OUT"

{
echo
echo "## Production build"
} | tee -a "$OUT"
timeout 600 "$PNPM" build 2>&1 | tail -16 | sed 's/^/  /' | tee -a "$OUT"
BUILD_RC=${PIPESTATUS[0]}

{
echo
echo "## Versions AS INSTALLED, read from the resolved dependency tree"
echo "  package.json records the request; the installed tree records the resolution."
echo
echo "  The first version of this section grepped pnpm-lock.yaml by package name and produced"
echo "  WRONG NUMBERS under a PASS verdict: it reported react 19.2.18 (that is @types/react)"
echo "  and vite 4.3.3 (that is tailwindcss). A verdict saying \"versions as pinned\" above a"
echo "  table of mismatched versions is exactly the fake win this build is supposed to catch,"
echo "  and I wrote it. Substring grep over a lockfile is not a parser. Asking pnpm is."
echo "  lockfile present: $([ -f pnpm-lock.yaml ] && echo "yes, $(stat -c%s pnpm-lock.yaml) bytes" || echo NO)"
echo
} | tee -a "$OUT"

"$PNPM" list --depth 0 --json 2>/dev/null > /home/zulab/ui-tree.json
/home/zulab/.asml-venv/bin/python "$REPO/scripts/pnpm_versions.py" 2>&1 | tee -a "$OUT"
VER_RC=${PIPESTATUS[0]}

{
echo
echo "## Pinned-by-decision, with the reason"
echo "  @tanstack/react-table 8.21.3, NOT v9. v9 renames useReactTable and moves the row"
echo "  models, and the shadcn data-table examples are not v9-compatible. Recorded as a"
echo "  decision in TASKS.md 1.15, not as a discovery here."
echo "  lightweight-charts 5.2.0. Pinned by decision."
echo
echo "## Build output"
ls -la dist 2>/dev/null | head -8 | sed 's/^/    /'
echo "    dist total: $(du -sh dist 2>/dev/null | cut -f1)"

echo
echo "## Verdict, task 1.15"
if [ "${BUILD_RC:-1}" -eq 0 ] && [ -f "$UI/dist/index.html" ] && [ "${VER_RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. Production build succeeded, lockfile written, and every installed"
  echo "  version was CHECKED against its pin by scripts/pnpm_versions.py, which exits"
  echo "  non-zero on any mismatch. The verdict is gated on that check, so it can no longer"
  echo "  say \"versions as pinned\" while printing versions that are not."
  echo "  Reproduce: bash scripts/61-frontend-scaffold.sh"
  echo "  GATE INTACT: the only source file is a placeholder that names the gate. No UI has"
  echo "  been written and none will be until evidence/ui-study.md exists."
else
  echo "  RESULT: FAIL. build exit $BUILD_RC, dist/index.html $([ -f "$UI/dist/index.html" ] && echo present || echo missing), version check exit ${VER_RC:-1}."
fi
} | tee -a "$OUT"

echo "written: $OUT"
