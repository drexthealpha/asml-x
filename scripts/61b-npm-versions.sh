#!/usr/bin/env bash
# R-SEARCH-1 for task 1.15: the pins in 61-frontend-scaffold.sh came from memory, and package
# versions are the canonical fast-changing fact. Ask the registry before installing, so a
# nonexistent exact version fails here, in a probe, instead of inside the scaffold.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
export PATH="/home/zulab/.npm-global/bin:$PATH"
for P in react react-dom @tanstack/react-table lightweight-charts lucide-react framer-motion \
         class-variance-authority clsx tailwind-merge @types/react @types/react-dom \
         @vitejs/plugin-react typescript vite tailwindcss @tailwindcss/vite; do
  printf '%-28s latest=%-12s' "$P" "$(npm view "$P" version 2>/dev/null || echo ERR)"
  # For the two pinned-by-decision packages, confirm the EXACT pin exists.
  case "$P" in
    @tanstack/react-table) printf ' 8.21.3-exists=%s' "$(npm view '@tanstack/react-table@8.21.3' version 2>/dev/null || echo NO)";;
    lightweight-charts)    printf ' 5.2.0-exists=%s'  "$(npm view 'lightweight-charts@5.2.0' version 2>/dev/null || echo NO)";;
  esac
  echo
done
