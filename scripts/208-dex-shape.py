"""Dump the real shapes of the OKX v6 DEX responses, so the integration uses actual fields."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from okx_dex import creds, signed_get  # noqa: E402

c = creds()
if not c:
    print("no credentials")
    sys.exit(2)

toks = signed_get("/api/v6/dex/aggregator/all-tokens?chainIndex=196", c)
print("=== X Layer tokens (first 8) ===")
for t in (toks.get("data") or [])[:8]:
    print(f"  {t.get('tokenSymbol'):10} {t.get('tokenContractAddress')}  dec={t.get('decimals')}")

q = signed_get(
    "/api/v6/dex/aggregator/quote?chainIndex=196&amount=1000000000000000000"
    "&fromTokenAddress=0xe538905cf8410324e03a5a23c1c177a474d59b2b"
    "&toTokenAddress=0x1e4a5963abfd975d8c9021ce480b42188849d41d",
    c,
)
print()
print("=== quote payload ===")
print(json.dumps((q.get("data") or [{}])[0], indent=2)[:1800])
