"""A stand-in for Control's /api/readiness/ingest, for the self-test.

    python3 fake_control.py PORT LOG

Every POST is answered 201 and appended to LOG as one JSON line: the parsed body, and whether an
X-GitHub-OIDC-Token header arrived. The token itself is never written anywhere.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
LOG = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self._answer(200, {"ok": True})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length)
        try:
            body = json.loads(raw)
        except ValueError:
            body = {"unparseable": raw.decode("utf-8", "replace")}
        record = {
            "path": self.path,
            "content_type": self.headers.get("Content-Type"),
            "has_token": bool(self.headers.get("X-GitHub-OIDC-Token")),
            "body": body,
        }
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record) + "\n")
        self._answer(201, {"ok": True, "created": True})

    def _answer(self, code, payload):
        data = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
