"""Patch the product gate: separate the API base from the page URL, and finish the BUNDLE rename.

Written as a file rather than an inline node -e because the shell strips `$` and backslashes on the
way through, which is CLAUDE.md E4 and has now bitten thirteen times.
"""
import os
import re

p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "234-product-gate.sh")
s = open(p, encoding="utf-8").read()

if "ASML_API" not in s:
    s = s.replace(
        'URL="${ASML_URL:-https://asml-x.vercel.app}"',
        'URL="${ASML_URL:-https://asml-x.vercel.app}"\n\n'
        "# THE API LIVES SOMEWHERE ELSE LOCALLY. Hosted, the serverless functions sit at the same\n"
        "# origin as the page. Locally the static server is 4173 and the signing feed server is 8787,\n"
        "# so pointing both at one base reported five false 404s. A gate that fails on its own\n"
        "# configuration teaches people to ignore it, which is worse than having no gate.\n"
        'case "$URL" in\n'
        '  *127.0.0.1*|*localhost*) API="${ASML_API:-http://127.0.0.1:8787}" ;;\n'
        '  *) API="$URL" ;;\n'
        "esac",
    )

s = s.replace('"$URL/api/', '"$API/api/')
s = re.sub(r'"\$BUNDLE"', '"$BUNDLE_DIR"', s)
s = s.replace('echo "target $URL"', 'echo "target $URL"\necho "api    $API"')

open(p, "w", encoding="utf-8", newline="\n").write(s)
print("patched")
print("  API base:", "yes" if "ASML_API" in s else "NO")
print("  stray $BUNDLE:", s.count('"$BUNDLE"'))
