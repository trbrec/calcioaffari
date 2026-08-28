import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        return

    def _json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        if self.path == "/api/tags":
            self._json(200, {"models": [{"name": "qwen3:14b"}]})
            return
        self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/api/generate":
            self._json(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        time.sleep(30)
        self._json(200, {"response": '{"ok":true}'})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18999), Handler).serve_forever()
