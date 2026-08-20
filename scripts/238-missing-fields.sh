#!/usr/bin/env bash
# Which fields the advanced-info and security endpoints ACTUALLY return for a tokenized equity.
#
# WHY. The full RWA feed shows 1 of 7 contract fields and 5 of 9 security fields for TSLAx. Two
# explanations are possible and they need opposite responses:
#
#   A. the endpoint returns them under different key names, and the parser is wrong
#   B. the endpoint genuinely does not have them for this token
#
# Guessing between those is how a UI ends up rendering "not available" for data that was there, or
# inventing a key that never existed. This prints the RAW response so the answer is read rather
# than assumed.
#
# EVIDENCE PATH: evidence/phase21/missing-fields.txt
set -uo pipefail
cd "$(dirname "$0")"

OUT="../evidence/phase21/missing-fields.txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee "$OUT") 2>&1

TSLA=$(python3 -c "
import json
d=json.load(open('../ui-v2/public/data/rwa-full.json'))
print([i['address'] for i in d['instruments'] if i['symbol']=='TSLAx'][0])
")
echo "TSLAx $TSLA"

echo
echo "=== advanced-info, every key it returns ==="
bash oos.sh --chain xlayer token advanced-info --address "$TSLA" < /dev/null 2>&1 | tail -c 2000 | python3 -c '
import json,sys
raw=sys.stdin.read(); i=raw.find("{")
d=json.loads(raw[i:]) if i>=0 else {}
data=d.get("data") or {}
if isinstance(data,list): data=data[0] if data else {}
for k,v in sorted(data.items()):
    print(f"  {k:<28} {str(v)[:50]}")
'

echo
echo "=== security token-scan, every key it returns ==="
bash oos.sh --chain xlayer security token-scan --tokens "196:$TSLA" < /dev/null 2>&1 | tail -c 2000 | python3 -c '
import json,sys
raw=sys.stdin.read(); i=raw.find("{")
d=json.loads(raw[i:]) if i>=0 else {}
data=d.get("data") or []
row=data[0] if isinstance(data,list) and data else (data if isinstance(data,dict) else {})
for k,v in sorted(row.items()):
    print(f"  {k:<28} {str(v)[:50]}")
'

echo
echo "=== basic-info, in case the contract facts live there instead ==="
bash oos.sh --chain xlayer token info --address "$TSLA" < /dev/null 2>&1 | tail -c 1500 | python3 -c '
import json,sys
raw=sys.stdin.read(); i=raw.find("{")
d=json.loads(raw[i:]) if i>=0 else {}
data=d.get("data") or []
row=data[0] if isinstance(data,list) and data else (data if isinstance(data,dict) else {})
for k,v in sorted(row.items()):
    print(f"  {k:<28} {str(v)[:50]}")
'
