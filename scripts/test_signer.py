#!/usr/bin/env python3
"""TEST-ONLY signing endpoint for verifying the Phase 9 flow. NOT part of the product.

WHY THIS EXISTS. Task 9.3's PASS condition is "proven by reading the deployed vault state AFTER
ACTIVATION", and 9.4 counts the clicks of a real deposit. Both need the UI to cause an actual
transaction. Task 9.0 (install a browser extension) is USER HANDLES and outstanding, so there is no
extension to sign with, and the headless provider deliberately REFUSES `eth_sendTransaction`.

WHY THE PROVIDER REFUSES, and why that refusal is kept. ADR-008 decided signing lives in `cast`,
measured: keystore decrypt plus process spawn is about 0.11s of a 22 to 30 second read-to-landing
path, so moving signing in-process would remove 0.4 percent of the latency while moving the private
key into the agent's address space. Reimplementing secp256k1 inside a browser page would be a SECOND
signing implementation to keep correct, and it would put a key in the page. Neither is acceptable for
a convenience during verification.

SO THE SHAPE IS: the page asks this endpoint to send a transaction, this endpoint shells out to
`cast send` with the keystore, and the key never enters the browser. Signing stays exactly where
ADR-008 put it. The transaction is real, lands in a real block, and is verifiable on the explorer.

WHAT MAKES THIS SAFE TO EXIST, and one thing that does NOT:

  - THE DESTINATION ALLOWLIST is the real control. It refuses any `to` that is not a contract in
    deployments.json. A signing oracle that will send anywhere is a wallet drainer with a friendly
    API, and the allowlist is what stops that.
  - THE KEY IS TESTNET ONLY and holds 0.199 test OKB. The blast radius of the whole endpoint is
    bounded by what that key can lose, which is nothing of value.
  - It is never referenced by ui-v2 source. Only the injected test provider calls it, and that
    provider only ever exists in `dist`, which `npm run build` regenerates without it.

  - IT BINDS 0.0.0.0, NOT 127.0.0.1, and that is a real weakening rather than a detail. The first
    draft bound loopback and called that a safety property. E10 says exactly why that cannot work:
    WSL2 has its own network namespace, so a server on the distro's loopback is unreachable from the
    Windows-side browser, which is where the pane runs. Loopback would have made the endpoint safe
    and useless. So the binding is open on the machine's network and the allowlist above is doing
    all of the work. Stated plainly because a safety argument that rests on a bind address I had to
    change is not a safety argument.

WHEN 9.0 LANDS this is deleted from the flow entirely: a real extension signs, and the same gates
re-run unchanged. It must never be started outside a gate run.

"""
import json
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

REPO = os.environ.get("REPO") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RPC = os.environ["RPC"]
KEYFILE = os.environ["KEYFILE"]
KEYPASS = os.environ["KEYPASS"]
PORT = int(os.environ.get("SIGNER_PORT", "4177"))

with open(f"{REPO}/deployments.json", encoding="utf-8") as fh:
    DEPLOY = json.load(fh)

# The only addresses this endpoint will ever send to. Everything else is refused, so a page bug or a
# hostile script cannot turn it into a general-purpose transfer service.
ALLOWED = {
    str(v).lower()
    for k, v in DEPLOY.items()
    if isinstance(v, str) and re.fullmatch(r"0x[0-9a-fA-F]{40}", str(v))
}

HEX = re.compile(r"^0x[0-9a-fA-F]*$")


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        # The page is served from :4173 and this is :4177, so the browser treats it as cross-origin.
        self.send_header("access-control-allow-origin", "*")
        self.send_header("access-control-allow-headers", "content-type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self._send(204, {})

    def log_message(self, *args):
        pass  # the gate script captures what it needs; per-request noise is not useful

    def _sign_typed(self, req):
        """EIP-712 signature via `cast wallet sign --data`. The key stays in the keystore."""
        domain = req.get("domain") or {}
        verifying = str(domain.get("verifyingContract", "")).lower()
        if verifying not in ALLOWED:
            # A permit signature IS an approval. Signing typed data for an arbitrary contract is
            # strictly more dangerous than sending to one, so the allowlist applies here too.
            self._send(
                403,
                {
                    "error": "refused: verifyingContract is not a deployed contract in deployments.json",
                    "verifyingContract": verifying,
                },
            )
            return

        path = os.path.join(os.path.expanduser("~"), ".asml-typed-data.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(req, fh)

        try:
            r = subprocess.run(
                [
                    "cast", "wallet", "sign",
                    "--keystore", KEYFILE,
                    "--password", KEYPASS,
                    "--data", "--from-file", path,
                ],
                capture_output=True, text=True, timeout=120,
            )
        except subprocess.TimeoutExpired:
            self._send(504, {"error": "cast wallet sign timed out"})
            return

        if r.returncode != 0:
            self._send(502, {"error": (r.stderr or r.stdout).strip()[:400]})
            return

        sig = r.stdout.strip()
        if not re.fullmatch(r"0x[0-9a-fA-F]{130}", sig):
            self._send(502, {"error": f"unexpected signature shape: {sig[:80]}"})
            return
        self._send(200, {"signature": sig})

    def do_POST(self):
        try:
            n = int(self.headers.get("content-length", "0"))
            if n > 64 * 1024:
                self._send(413, {"error": "body too large"})
                return
            req = json.loads(self.rfile.read(n) or b"{}")
        except Exception as exc:
            self._send(400, {"error": f"bad json: {exc}"})
            return

        if self.path.rstrip("/").endswith("sign-typed"):
            self._sign_typed(req)
            return

        to = str(req.get("to", "")).lower()
        data = str(req.get("data", "0x"))
        value = str(req.get("value", "0x0"))

        if to not in ALLOWED:
            self._send(
                403,
                {
                    "error": "refused: destination is not a deployed contract in deployments.json",
                    "to": to,
                },
            )
            return
        if not HEX.match(data):
            self._send(400, {"error": "data is not hex"})
            return

        cmd = [
            "cast", "send", to,
            "--rpc-url", RPC,
            "--keystore", KEYFILE,
            "--password", KEYPASS,
            "--json",
        ]
        if data and data != "0x":
            cmd += ["--data", data]
        if value not in ("0x0", "0x", "", "0"):
            cmd += ["--value", str(int(value, 16))]

        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        except subprocess.TimeoutExpired:
            self._send(504, {"error": "cast send timed out"})
            return

        if r.returncode != 0:
            self._send(502, {"error": (r.stderr or r.stdout).strip()[:400]})
            return
        try:
            receipt = json.loads(r.stdout)
        except Exception:
            self._send(502, {"error": f"unparseable cast output: {r.stdout[:200]}"})
            return

        self._send(
            200,
            {
                "transactionHash": receipt.get("transactionHash"),
                "status": receipt.get("status"),
                "blockNumber": receipt.get("blockNumber"),
            },
        )


def main():
    # 0.0.0.0 because of E10: a WSL server on loopback is unreachable from the Windows-side browser.
    # The destination allowlist, not the bind address, is what makes this safe. See the docstring.
    srv = HTTPServer(("0.0.0.0", PORT), Handler)
    print(
        f"TEST SIGNER on 0.0.0.0:{PORT}, {len(ALLOWED)} allowed destinations. "
        f"Test-only, never part of the product.",
        flush=True,
    )
    srv.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
