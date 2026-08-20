"""Patch the product gate: section 3 to a real file, section 4 to a grep that survives the shell.

TWO GATE BUGS, both mine, both the same root cause. `wsl -- bash -c` strips escapes, so:
  - section 3's inline python had nested quotes inside an f-string and died with a NameError
  - section 4's `grep "a\\|b\\|c"` lost its escaped alternation and matched nothing

Both reported FAIL against a product that was fine. A gate that fails on its own quoting teaches
people to ignore it, which is worse than having no gate at all. Fixed-string greps and a real
python file remove the class of error.
"""
import os

p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "234-product-gate.sh")
s = open(p, encoding="utf-8").read()

# ---- section 3: call the file, against the right endpoint per environment
start = s.find('echo "=== 3.')
end = s.find('echo "=== 4.')
if start > 0 and end > start:
    s = s[:start] + (
        'echo "=== 3. the RWA surface carries deep datapoints ==="\n'
        "# The deep feed is /api/rwafull locally and /api/rwa when hosted: the serverless function\n"
        "# and the local script write the same shape under different names.\n"
        'case "$URL" in\n'
        '  *127.0.0.1*|*localhost*) RWA_EP="$API/api/rwafull" ;;\n'
        '  *) RWA_EP="$API/api/rwa" ;;\n'
        "esac\n"
        'if python3 "$(dirname "$0")/gate_rwa_depth.py" "$RWA_EP"; then\n'
        '  :\n'
        "else\n"
        "  FAIL=1\n"
        "fi\n\n"
    ) + s[end:]

# ---- section 4: fixed-string greps, one per phrase, no escaped alternation
start = s.find('echo "=== 4.')
end = s.find('echo "=== 5.')
if start > 0 and end > start:
    s = s[:start] + (
        'echo "=== 4. failure is never rendered as data ==="\n'
        "# Fixed strings, checked one at a time. An escaped alternation does not survive the shell\n"
        "# and silently matches nothing, which reported a fail against text that was present.\n"
        "FOUND=0\n"
        'for phrase in "is unavailable right now" "could not be read" "could not load" "Nothing is shown"; do\n'
        '  if grep -rqF "$phrase" "$BUNDLE_DIR" 2>/dev/null; then\n'
        "    FOUND=$((FOUND + 1))\n"
        "  fi\n"
        "done\n"
        'if [ "$FOUND" -ge 3 ]; then\n'
        '  pass "explicit unavailable states in the bundle ($FOUND of 4 phrases)"\n'
        "else\n"
        '  fail "only $FOUND of 4 unavailable-state phrases found"\n'
        "fi\n\n"
    ) + s[end:]

open(p, "w", encoding="utf-8", newline="\n").write(s)
print("patched")
print("  gate_rwa_depth called:", "yes" if "gate_rwa_depth.py" in s else "NO")
print("  fixed-string greps:", s.count("grep -rqF"))
