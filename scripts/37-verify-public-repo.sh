#!/usr/bin/env bash
# Phase 10 groundwork: verify the public repo and its first CI run.
# Uses GITHUB_TOKEN from ~/.profile so the API calls are not rate limited (the
# unauthenticated GitHub API rate-limited this project earlier).
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
load_all_creds

OWNER="drexthealpha"
NAME="asml-x"
API="https://api.github.com/repos/$OWNER/$NAME"
EVID="$REPO/evidence/submission"
mkdir -p "$EVID"

auth() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -sS --max-time 30 -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" "$1"
  else
    curl -sS --max-time 30 -H "Accept: application/vnd.github+json" "$1"
  fi
}

echo "=== repo metadata ==="
auth "$API" > /tmp/repo.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/repo.json'))
if 'message' in d and 'full_name' not in d:
    print("API ERROR:", d.get('message'))
    raise SystemExit(0)
for k in ['full_name', 'private', 'description', 'default_branch', 'size',
          'open_issues_count', 'license', 'pushed_at', 'html_url']:
    v = d.get(k)
    if isinstance(v, dict):
        v = v.get('spdx_id')
    print(f"  {k:20} {v}")
print(f"  {'PUBLIC':20} {not d.get('private', True)}")
PY

echo
echo "=== workflow runs (the first real CI run) ==="
auth "$API/actions/runs?per_page=5" > /tmp/runs.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/runs.json'))
runs = d.get('workflow_runs', [])
if not runs:
    print("  NO WORKFLOW RUNS. Either Actions is disabled for the repo, or the workflow")
    print("  file did not reach the default branch, or the trigger did not match.")
else:
    for r in runs:
        print(f"  {r['name']:22} {r['status']:12} {str(r.get('conclusion')):10} {r['head_branch']:8} {r['html_url']}")
PY

echo
echo "=== does the workflow file exist on the default branch? ==="
auth "$API/contents/.github/workflows" > /tmp/wf.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/wf.json'))
if isinstance(d, dict):
    print("  MISSING:", d.get('message'))
else:
    for f in d:
        print(f"  {f['name']}  {f['size']} bytes")
PY

echo
echo "=== secret scan on what was actually pushed ==="
auth "$API/contents/.gitignore" > /tmp/gi.json
python3 - <<'PY'
import base64, json
d = json.load(open('/tmp/gi.json'))
if 'content' in d:
    body = base64.b64decode(d['content']).decode()
    need = ['.env', 'keystore', '.asml-keys']
    for n in need:
        print(f"  .gitignore covers {n:14} {'yes' if n in body else 'NO'}")
else:
    print("  .gitignore not readable:", d.get('message'))
PY

echo
echo "=== is any secret-looking file present in the tree? ==="
auth "$API/git/trees/main?recursive=1" > /tmp/tree.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/tree.json'))
tree = d.get('tree', [])
if not tree:
    print("  tree not readable:", d.get('message'))
else:
    bad = [t['path'] for t in tree
           if any(k in t['path'].lower() for k in ['keystore', '.env', 'secret', '.pass', 'id_rsa'])
           and not t['path'].endswith('.example')]
    print(f"  files in tree: {len(tree)}")
    if bad:
        print("  SUSPICIOUS FILES PUSHED:")
        for b in bad:
            print("   ", b)
    else:
        print("  no keystore, .env, secret or .pass files in the pushed tree")
PY

cp /tmp/repo.json "$EVID/repo-metadata.json" 2>/dev/null || true
cp /tmp/runs.json "$EVID/ci-runs.json" 2>/dev/null || true
echo
echo "written: $EVID/"
