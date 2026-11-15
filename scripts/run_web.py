#!/usr/bin/env python3
"""Build the Web game, serve it locally and open the default browser."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import webbrowser


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error("port must be between 0 and 65535")

    root = Path(__file__).resolve().parents[1]
    build = subprocess.run(["bash", "scripts/export.sh", "web"], cwd=root)
    if build.returncode:
        return build.returncode

    handler = partial(SimpleHTTPRequestHandler, directory=str(root / "build/web"))
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    except OSError as error:
        print(f"Cannot start the local Web server on port {args.port}. {error}", file=sys.stderr)
        return 1

    with server:
        url = f"http://127.0.0.1:{server.server_port}/"
        print(f"Game ready at {url}\nPress Ctrl+C to stop the server.", flush=True)
        try:
            opened = webbrowser.open(url, new=2)
        except (webbrowser.Error, OSError):
            opened = False
        if not opened:
            print(f"Open {url} in your browser.", flush=True)
        server.serve_forever()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nWeb server stopped.")
