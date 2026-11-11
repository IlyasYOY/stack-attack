#!/usr/bin/env python3
"""Serve the Web export locally and test real canvas input and resizing."""
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import threading

from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parents[1]
output = root / "build"
screenshots = output / "screenshots"
screenshots.mkdir(parents=True, exist_ok=True)
if not (output / "web/index.html").is_file():
    raise SystemExit("Export Web first: bash scripts/export.sh web")


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


handler = functools.partial(QuietHandler, directory=str(output / "web"))
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
results = []
try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            executable_path=os.environ.get("CHROMIUM_BIN", "/usr/bin/chromium"),
            headless=True,
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
        )
        for touch, initial in [(False, (1280, 720)), (True, (390, 844)), (True, (320, 568))]:
            context = browser.new_context(
                viewport={"width": initial[0], "height": initial[1]},
                has_touch=touch, device_scale_factor=1,
            )
            page = context.new_page()
            errors = []
            failed_requests = []
            logs = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.on("requestfailed", lambda request: failed_requests.append(request.url))
            page.on("console", lambda message: logs.append(message.type + ": " + message.text))
            response = page.goto(f"http://127.0.0.1:{server.server_port}/index.html")
            assert response.status == 200
            page.wait_for_function("window.stackAttackTech?.ready === true", timeout=60000)
            sizes = [initial, (initial[1], initial[0])]
            for width, height in sizes:
                page.set_viewport_size({"width": width, "height": height})
                orientation = "landscape" if width > height else "portrait"
                page.wait_for_function(
                    "expected => window.stackAttackTech?.layout === expected", arg=orientation,
                )
                # Container geometry settles after the viewport signal.
                page.wait_for_timeout(250)
                state = page.evaluate("window.stackAttackTech")
                canvas = page.locator("canvas")
                assert canvas.is_visible()
                bounds = canvas.bounding_box()
                x, y, button_width, button_height = state["button"]
                viewport_width, viewport_height = state["viewport"]
                assert button_height >= 52
                assert x >= 0 and y >= 0
                assert x + button_width <= viewport_width + 1
                assert y + button_height <= viewport_height + 1, "Input button is clipped"
                center_x = bounds["x"] + (x + button_width / 2) * bounds["width"] / viewport_width
                center_y = bounds["y"] + (y + button_height / 2) * bounds["height"] / viewport_height
                if touch:
                    page.touchscreen.tap(center_x, center_y)
                else:
                    page.mouse.click(center_x, center_y)
                page.wait_for_function(
                    "before => window.stackAttackTech.clicks === before + 1", arg=state["clicks"],
                )
                if not touch:
                    page.keyboard.press("Enter")
                    page.wait_for_function(
                        "before => window.stackAttackTech.clicks === before + 2", arg=state["clicks"],
                    )
                screenshot = screenshots / f"{'touch' if touch else 'mouse'}-{width}x{height}.png"
                page.screenshot(path=str(screenshot))
                results.append({
                    "viewport": [width, height], "layout": orientation,
                    "input": "emulated touch" if touch else "mouse + keyboard",
                    "clicks": page.evaluate("window.stackAttackTech.clicks"),
                    "screenshot": str(screenshot.relative_to(root)),
                })
            assert not errors, errors
            assert not failed_requests, failed_requests
            assert not [line for line in logs if line.startswith("error:")], logs
            context.close()
        report = {"status": "PASS", "browser": browser.version, "renderer": "SwiftShader",
                  "pck_sha256": hashlib.sha256((output / "web/index.pck").read_bytes()).hexdigest(),
                  "page_errors": [], "failed_requests": [], "checks": results}
        browser.close()
        (output / "web-check.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
finally:
    server.shutdown()
    server.server_close()
