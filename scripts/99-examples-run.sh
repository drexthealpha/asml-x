#!/usr/bin/env bash
# Task 6.7: run BOTH example clients against the live API.
#
# THINKING: #12 design thinking (the reader is a builder deciding whether to depend on this), #50
# empirical (an example that has never been run is a snippet, not an example).
#
# PASS: both examples run against the live API and produce a quote.
#
# EVIDENCE PATH declared before code: evidence/phase6/examples-run.txt
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

PORT=8737
OUT="$REPO/evidence/phase6/examples-run.txt"
mkdir -p "$(dirname "$OUT")"

pkill -x asml-coord 2>/dev/null || true
sleep 1
ASML_RATE_LIMIT=200 ASML_REPO="$REPO" ASML_COORD_PORT=$PORT setsid nohup \
  ./target/release/asml-coord > /home/zulab/coord-6-7.log 2>&1 < /dev/null &
for i in $(seq 1 180); do
  curl -sS --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
  sleep 1
done

{
echo "Example clients, task 6.7"
echo "Run $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "  server up after ${i}s"
echo
echo "  Both examples are dependency-free and under 90 lines. A builder should be able to read one"
echo "  and know whether this surface is worth depending on."
echo
echo "## Python: examples/python_client.py"
echo "   lines: $(wc -l < examples/python_client.py)"
} 2>&1 | tee "$OUT"

PY_RC=0
timeout 120 python3 examples/python_client.py 2>&1 | sed 's/^/  /' | tee -a "$OUT" || PY_RC=$?
PY_RC=${PIPESTATUS[0]:-$PY_RC}

{
echo
echo "## TypeScript: examples/typescript_client.ts"
echo "   lines: $(wc -l < examples/typescript_client.ts)"
echo "   node: $(node --version 2>&1)"
} | tee -a "$OUT"

TS_RC=0
TSC="$REPO/ui-v2/node_modules/.bin/tsc"

# Compile with the REAL compiler, which also type-checks the example. Node 20 cannot run .ts directly
# (`--experimental-strip-types` arrived in 22.6), and stripping types with sed broke on the first
# optional parameter it met. typescript 5.9.3 is already installed for the terminal build.
if [ -x "$TSC" ]; then
  rm -rf /home/zulab/ts-example && mkdir -p /home/zulab/ts-example
  # No --types and no --typeRoots. The example declares the two host globals it uses, so it compiles
  # with nothing installed, which is the point of an example.
  if timeout 180 "$TSC" examples/typescript_client.ts \
      --outDir /home/zulab/ts-example \
      --module esnext --target es2022 --lib es2022,dom \
      --moduleResolution bundler --skipLibCheck \
      > /home/zulab/tsc-out.txt 2>&1; then
    echo "  type-checked and compiled with tsc $("$TSC" --version | awk '{print $2}')" | tee -a "$OUT"
    mv /home/zulab/ts-example/typescript_client.js /home/zulab/ts-example/typescript_client.mjs
    timeout 120 node /home/zulab/ts-example/typescript_client.mjs 2>&1 | sed 's/^/  /' | tee -a "$OUT"
    TS_RC=${PIPESTATUS[0]}
  else
    TS_RC=1
    echo "  tsc failed to compile the example:" | tee -a "$OUT"
    sed 's/^/    /' /home/zulab/tsc-out.txt | head -12 | tee -a "$OUT"
  fi
else
  TS_RC=1
  echo "  tsc not found at $TSC. Run pnpm install in ui-v2 first." | tee -a "$OUT"
fi

{
echo
echo "## Verdict, task 6.7"
echo "  python exit: $PY_RC"
echo "  typescript exit: $TS_RC"
if [ "${PY_RC:-1}" -eq 0 ] && [ "${TS_RC:-1}" -eq 0 ]; then
  echo "  RESULT: PASS. Both examples ran against the live API and produced a quote."
else
  echo "  RESULT: FAIL. An example that does not run is a snippet, not an example."
fi
} | tee -a "$OUT"

pkill -x asml-coord 2>/dev/null || true
echo "written: $OUT"
[ "${PY_RC:-1}" -eq 0 ] && [ "${TS_RC:-1}" -eq 0 ]
