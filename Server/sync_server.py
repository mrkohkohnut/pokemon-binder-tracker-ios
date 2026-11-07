#!/usr/bin/env python3
"""Poké Binder sync server. Stdlib only, Python 3.9+.

Speaks the same /api/sync protocol as the web app, so the iOS app can point at either:
  GET /api/sync   (Authorization: Bearer <sync code>)                    -> {"collection": {...}}
  PUT /api/sync   (Authorization: Bearer <sync code>) {"collection": {...}} -> {"ok": true}
The sync code is the secret: each code is its own binder, stored under the SHA-256 of the code.
Run:       python3 sync_server.py
Self-test: python3 sync_server.py --test
"""
import hashlib, json, os, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.environ.get("SYNC_DATA", os.path.join(HERE, "binders"))
PORT = int(os.environ.get("SYNC_PORT", "8767"))
HOST = os.environ.get("SYNC_HOST", "127.0.0.1")
MAX_BODY = 10_000_000
lock = threading.Lock()  # ponytail: one global lock + whole-file rewrite, fine for a few phones


def path_for(code):
    return os.path.join(DATA, hashlib.sha256(code.encode()).hexdigest() + ".json")


def valid_code(code):
    return len(code) >= 20 and code.isalnum()


def load(code):
    try:
        with open(path_for(code)) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save(code, collection):
    os.makedirs(DATA, exist_ok=True)
    target = path_for(code)
    tmp = target + ".tmp"
    with open(tmp, "w") as f:
        json.dump(collection, f)
    os.replace(tmp, target)  # atomic: a crash mid-write never corrupts the binder


class Handler(BaseHTTPRequestHandler):
    def code(self):
        auth = self.headers.get("Authorization", "")
        code = auth[7:].strip() if auth.startswith("Bearer ") else ""
        return code if valid_code(code) else None

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/api/sync":
            return self.reply(404, {"error": "Not found"})
        code = self.code()
        if code is None:
            return self.reply(401, {"error": "Missing or invalid sync code"})
        with lock:
            collection = load(code)
        self.reply(200, {"collection": collection})

    def do_PUT(self):
        if self.path != "/api/sync":
            return self.reply(404, {"error": "Not found"})
        code = self.code()
        if code is None:
            return self.reply(401, {"error": "Missing or invalid sync code"})
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > MAX_BODY:
                return self.reply(413, {"error": "Binder too large"})
            collection = json.loads(self.rfile.read(length))["collection"]
            assert isinstance(collection, dict)
        except Exception:
            return self.reply(400, {"error": "Expected {\"collection\": {...}}"})
        with lock:
            save(code, collection)
        self.reply(200, {"ok": True})

    def log_message(self, fmt, *args):  # never log sync codes; only method, path and status
        sys.stderr.write("%s %s\n" % (self.command, " ".join(str(a) for a in args[1:2])))


if __name__ == "__main__":
    if "--test" in sys.argv:
        import tempfile
        DATA = tempfile.mkdtemp()
        code = "A" * 20
        assert load(code) == {}
        save(code, {"1": {"cardId": "x"}})
        assert load(code) == {"1": {"cardId": "x"}}
        assert load("B" * 20) == {}
        assert not valid_code("short") and not valid_code("A" * 19 + "-")
        print("ok")
        sys.exit()
    print(f"Poké Binder sync on {HOST}:{PORT}, data in {DATA}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
