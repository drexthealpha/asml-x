#!/usr/bin/env bash
# Task 14.3 verification: does the OpenTelemetry stdout exporter actually EMIT, or is the SDK merely
# linked in?
#
# This exists because the first pass of 14.3 checked only the JSON-lines file this repo writes, and
# that file would look identical whether the SDK were wired or not. The SDK's own exporter output is
# the only thing that distinguishes "using OpenTelemetry" from "linking OpenTelemetry".
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
cd "$REPO"

OUT="$REPO/evidence/phase14/otel-stdout.txt"
mkdir -p "$(dirname "$OUT")"

ASML_REPO="$REPO" ./target/release/asml run 1 > "$OUT" 2>&1
echo "exit: $?"
echo "lines: $(wc -l < "$OUT")"
echo
echo "=== SDK exporter markers ==="
grep -c "Name *:" "$OUT" || true
grep -n "Name *:\|Parent Span Id\|TraceId\|Trace Id\|SpanId\|Span Id\|Instrumentation Scope" "$OUT" | head -40
