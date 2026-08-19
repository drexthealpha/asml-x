"""Live feed server. Signs OKX requests server-side and serves fresh prices to the browser.

WHY THIS EXISTS. Every price in the app came from a JSON file written once by a script, so the
screen showed whatever the last manual run happened to fetch. It looked hardcoded because
functionally it was: nothing refreshed it, ever.

WHY THE BROWSER CANNOT DO THIS ITSELF. The Onchain OS endpoints need an HMAC signature over the
request, which needs the API secret. A secret shipped to a browser is a published secret. So the
signing stays here, on the machine, and the browser sees only the results.

WHAT IT SERVES, all refreshed on a timer, never on a page load (so twenty open tabs do not become
twenty times the API traffic):

  /api/universe   every X Layer token, priced and route-checked
  /api/market     OKB-USDT top of book, candles, realized volatility
  /api/rwa        treasury-backed tokens and their distance from a dollar
  /api/depth      the measured cost of size
  /api/chain      the deployment manifest, straight off disk

CACHE POLICY. Each feed has its own interval, because they change at different speeds: a price
moves every second, a token listing does not. A request between refreshes is served the cached
copy with its age attached, so the UI can say how old a number is instead of implying it is live.

FAILURE IS REPORTED, NOT PAPERED OVER. If a refresh fails the previous value is kept and marked
stale. Serving a stale price labelled stale is honest; serving it labelled live is not.
"""
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(REPO, "ui-v2", "public", "data")
PORT = int(os.environ.get("FEED_PORT", "8787"))

# Seconds between refreshes, per feed. Prices move constantly; a token listing does not.
INTERVALS = {
    "market": 10,
    "universe": 60,
    "rwa": 30,
    "depth": 45,
    "onchainos": 20,
    "intel": 45,
    "detail": 90,
    "rwastate": 60,
    "activity": 8,
}

_lock = threading.Lock()
_cache = {}


def _run(module_name):
    """Run one feed script in-process and read back the file it wrote.

    In-process rather than as a subprocess so the token list cached in `tokens.py` is shared across
    every feed, which is the difference between one all-tokens call per refresh cycle and four.
    """
    import importlib

    mod = importlib.import_module(module_name)
    importlib.reload(mod)
    rc = mod.main()
    return rc == 0


FEEDS = {
    "market": ("okx_market", "market.json"),
    "universe": ("okx_universe", "universe.json"),
    "rwa": ("okx_rwa", "rwa.json"),
    "depth": ("okx_depth", "depth.json"),
    "onchainos": ("oos_all", "onchainos.json"),
    "intel": ("oos_intel", "intel.json"),
    "detail": ("oos_detail", "detail.json"),
    "rwastate": ("rwa_state", "rwa-state.json"),
    "activity": ("agent_activity", "activity.json"),
}


def refresh(name):
    module, filename = FEEDS[name]
    try:
        ok = _run(module)
    except Exception as exc:  # a failing feed must not take the server down
        ok = False
        print(f"  {name}: {type(exc).__name__}: {exc}")

    path = os.path.join(DATA, filename)
    try:
        with open(path, encoding="utf-8") as fh:
            value = json.load(fh)
    except OSError:
        return

    with _lock:
        _cache[name] = {
            "value": value,
            "at": time.time(),
            # A refresh that failed leaves the previous file in place. Saying so lets the UI show
            # the age rather than presenting a stale number as current.
            "fresh": ok,
        }
    print(f"  {name}: {'refreshed' if ok else 'STALE, kept previous'}")


def loop(name):
    while True:
        refresh(name)
        time.sleep(INTERVALS[name])


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        # The UI is served from a different port in development. Read-only public market data.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        path = self.path.split("?")[0].rstrip("/")

        if path == "/api/chain":
            try:
                with open(os.path.join(DATA, "deployments.json"), encoding="utf-8") as fh:
                    return self._send(200, json.load(fh))
            except OSError as e:
                return self._send(503, {"error": str(e)})

        if path.startswith("/api/"):
            name = path[len("/api/") :]
            if name not in FEEDS:
                return self._send(404, {"error": f"no feed named {name}"})
            with _lock:
                entry = _cache.get(name)
            if not entry:
                # Honest 503: the first refresh has not completed. NOT an empty object, which a
                # client would render as a market with no prices.
                return self._send(503, {"error": "not fetched yet", "retry_in_s": 3})
            return self._send(
                200,
                {
                    **entry["value"],
                    "_age_s": round(time.time() - entry["at"], 1),
                    "_fresh": entry["fresh"],
                },
            )

        self._send(404, {"error": "not found"})

    def log_message(self, *_):
        """Silent. The refresh loop already reports what matters."""


def main():
    print(f"ASML-X feed server on http://0.0.0.0:{PORT}")
    print("refresh intervals: " + ", ".join(f"{k} {v}s" for k, v in INTERVALS.items()))
    for name in FEEDS:
        threading.Thread(target=loop, args=(name,), daemon=True).start()
    # 0.0.0.0, not 127.0.0.1: under WSL a loopback bind is unreachable from the Windows browser.
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
