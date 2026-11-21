"""Start the actual ZIP over HTTP and wait for the release game's initial scene."""
import functools
import http.server
import os
from pathlib import Path
import sys
import tempfile
import threading
import zipfile

from playwright.sync_api import sync_playwright

required = ["index.html", "index.wasm", "index.js", "index.pck"]
with tempfile.TemporaryDirectory() as directory, zipfile.ZipFile(sys.argv[1]) as archive:
    for name in required:
        if archive.getinfo(name).file_size == 0:
            raise ValueError(f"Empty {name}")
    for name in ("GODOT_LICENSE.txt", "GODOT_COPYRIGHT.txt"):
        if archive.read(name) != Path("notices", name).read_bytes():
            raise ValueError(f"Incorrect {name}")
    archive.extractall(directory)
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=directory)
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path=os.environ["CHROMIUM_BIN"],
                args=["--enable-unsafe-swiftshader", "--use-gl=angle", "--use-angle=swiftshader"])
            page = browser.new_page()
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            with page.expect_console_message(predicate=lambda msg: "STACK_ATTACK_READY" in msg.text,
                                             timeout=90000):
                page.goto(f"http://127.0.0.1:{server.server_port}/")
            if errors or not page.locator("canvas").is_visible():
                raise RuntimeError(f"Game startup failed: {errors}")
            print(f"Web ZIP booted in Chromium {browser.version}: STACK_ATTACK_READY")
            browser.close()
        server.shutdown()
