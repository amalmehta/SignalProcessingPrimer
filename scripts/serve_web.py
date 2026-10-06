#!/usr/bin/env python3
"""Serve the website locally the way the Artifact host does.

The published page (web/index.html) has no <!doctype>/<head>/<body> of its own — the host wraps it.
This server adds the same wrapper, serves the shared content/course.json at /course.json, and
everything else from web/. Usage: python3 scripts/serve_web.py [port]   (default $PORT or 8000)
"""
import http.server
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB, COURSE = ROOT / "web", ROOT / "content" / "course.json"
SKELETON = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>:root{{color-scheme:light}}body{{margin:0}}img{{max-width:100%}}[hidden]{{display:none!important}}</style>
</head><body>{page}</body></html>"""


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB), **kwargs)

    def do_GET(self):
        path = self.path.split("?")[0].split("#")[0]
        if path in ("/", "/index.html"):
            return self._send(SKELETON.format(page=(WEB / "index.html").read_text()).encode(), "text/html; charset=utf-8")
        if path == "/course.json":
            return self._send(COURSE.read_bytes(), "application/json")
        return super().do_GET()

    def _send(self, body, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("PORT", 8000))
    Handler.extensions_map[".js"] = "text/javascript"
    print(f"Signal Processing Primer website → http://localhost:{port}/")
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
