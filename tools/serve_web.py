#!/usr/bin/env python3
"""Serves the love.js build (dist/web) locally with the headers it needs.

The normal (threaded) love.js build uses SharedArrayBuffer, which browsers
only enable on cross-origin isolated pages. `python -m http.server` does not
send these headers, so the game would fail to start there.

Usage: python3 tools/serve_web.py [dir] [port]     (defaults: dist/web 8000)
"""

import functools
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class IsolatedHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")  # always the latest build
        super().end_headers()


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else "dist/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8000
    handler = functools.partial(IsolatedHandler, directory=directory)
    server = ThreadingHTTPServer(("127.0.0.1", port), handler)
    print(f"Serving {directory} at http://localhost:{port}/  (Ctrl+C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
