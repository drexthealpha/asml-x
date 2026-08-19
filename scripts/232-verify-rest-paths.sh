#!/usr/bin/env bash
# Verify EVERY REST path the Vercel functions use, against the live API, before they ship.
#
# WHY THIS EXISTS. The serverless functions were written by transcribing what the `onchainos` CLI
# does into REST calls, from memory. Several were wrong: `market/price` is a POST that takes a JSON
# body, and the functions called it as a GET with query parameters. A wrong path does not throw —
# the helper returns null, the field becomes null, and the page renders "no price" for a token that
# has one. On the deployed site that produced 0 priced instruments out of 8, which reads as a dead
# market rather than a broken client.
#
# This is the same failure as the invented contract selectors, in a different layer: a call that
# silently returns nothing looks exactly like an honest absence.
#
# Every path below is exercised against the real API. A path that does not return data does not go
# into a function.
#
# EVIDENCE PATH: evidence/phase20/rest-paths.txt
set -uo pipefail
cd "$(dirname "$0")"

OUT="../evidence/phase20/rest-paths.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

python3 verify_rest_paths.py
