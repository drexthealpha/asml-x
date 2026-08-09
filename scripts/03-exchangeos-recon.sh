#!/usr/bin/env bash
# Task 0.3.3 / 1.3.x groundwork: establish from PRIMARY sources whether Exchange
# OS is reachable on X Layer testnet, and pull the whitepaper as a hypothesis
# document (never as ground truth, per the reverse-engineering mandate).
# NOTE: /tmp does not persist across `wsl --` invocations here, so everything
# lands under the repo or $HOME. Not investigated further (R17).
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh

WORK="$REPO/evidence/exchangeos-recon"
DOCS="$REPO/docs/verified"
mkdir -p "$WORK" "$DOCS"

echo "=== fetch Exchange OS whitepaper (primary source) ==="
curl -sS --max-time 120 --resolve web3.okx.com:443:172.64.144.82 -L \
  -A "Mozilla/5.0 Chrome/126" \
  -o "$WORK/okx-exchange-os.pdf" \
  -w 'HTTP %{http_code} bytes=%{size_download}\n' \
  "https://web3.okx.com/whitepaper/okx-exchange-os.pdf"

python3 - <<'PY'
import os, re
from pypdf import PdfReader
work = os.environ['REPO'] + '/evidence/exchangeos-recon'
r = PdfReader(work + '/okx-exchange-os.pdf')
t = "\n".join((p.extract_text() or "") for p in r.pages)
open(work + '/whitepaper.txt', 'w', encoding='utf-8').write(t)
print("pages:", len(r.pages), "chars:", len(t))

# Hunt for the two things that decide the build: testnet presence and addresses.
addrs = sorted(set(re.findall(r'0x[0-9a-fA-F]{40}', t)))
print("\n--- ethereum addresses found in whitepaper:", len(addrs))
for a in addrs[:20]:
    print("   ", a)

for kw in ['testnet', 'Testnet', 'TradeZone', 'Trade Zone', 'XIP', 'stake', 'OKB',
           'matching', 'margin', 'outcome', 'perpetual', 'settlement', 'API',
           'sequencer', 'latency', 'Q3', 'Q4', 'roadmap', 'Roadmap']:
    n = t.count(kw)
    if n:
        print(f"kw {kw!r}: {n}")
PY

echo
echo "=== extract testnet-relevant passages ==="
grep -oiE '.{200}testnet.{240}' "$WORK/whitepaper.txt" | head -6

echo
echo "=== extract roadmap / phasing passages ==="
grep -oiE '.{120}(roadmap|phase [0-9]|Q3 2026|Q4 2026|mainnet launch).{260}' "$WORK/whitepaper.txt" | head -8
